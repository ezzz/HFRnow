#import "SDWebImage.h"
#import <objc/runtime.h>

@interface _SDWebImageTaskOperation : NSObject <SDWebImageOperation>
@property (nonatomic, strong, nullable) NSURLSessionDataTask *task;
@end

@implementation _SDWebImageTaskOperation
- (void)cancel {
    [self.task cancel];
}
@end

@implementation SDImageCache

+ (instancetype)sharedImageCache {
    static SDImageCache *cache;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        cache = [SDImageCache new];
    });
    return cache;
}

- (void)clearMemory {
    [[NSURLCache sharedURLCache] removeAllCachedResponses];
}

@end

@implementation SDWebImageDownloader

+ (instancetype)sharedDownloader {
    static SDWebImageDownloader *downloader;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        downloader = [SDWebImageDownloader new];
    });
    return downloader;
}

- (id<SDWebImageOperation>)downloadImageWithURL:(NSURL *)url
                                        options:(SDWebImageDownloaderOptions)options
                                       progress:(SDWebImageDownloaderProgressBlock)progressBlock
                                      completed:(SDWebImageDownloaderCompletedBlock)completedBlock {
    if (url == nil) {
        if (completedBlock) {
            NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil];
            dispatch_async(dispatch_get_main_queue(), ^{
                completedBlock(nil, nil, error, YES);
            });
        }
        return nil;
    }

    if (progressBlock) {
        dispatch_async(dispatch_get_main_queue(), ^{
            progressBlock(0, 0, url);
        });
    }

    NSURLRequestCachePolicy cachePolicy = (options & SDWebImageDownloaderUseNSURLCache)
        ? NSURLRequestUseProtocolCachePolicy
        : NSURLRequestReloadIgnoringLocalCacheData;

    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url cachePolicy:cachePolicy timeoutInterval:10.0];
    request.HTTPShouldHandleCookies = (options & SDWebImageDownloaderHandleCookies) != 0;

    __block _SDWebImageTaskOperation *operation = [_SDWebImageTaskOperation new];
    NSURLSessionDataTask *task = [[NSURLSession sharedSession] dataTaskWithRequest:request
                                                                  completionHandler:^(NSData * _Nullable data, NSURLResponse * _Nullable response, NSError * _Nullable error) {
        UIImage *image = data.length > 0 ? [UIImage imageWithData:data] : nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (progressBlock) {
                NSInteger expected = 0;
                if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
                    expected = (NSInteger)response.expectedContentLength;
                }
                progressBlock((NSInteger)data.length, expected, url);
            }
            if (completedBlock) {
                completedBlock(image, data, error, YES);
            }
        });
    }];

    operation.task = task;
    [task resume];
    return operation;
}

@end

static const void *kSDWebImageOperationKey = &kSDWebImageOperationKey;
static const void *kSDWebImageURLKey = &kSDWebImageURLKey;

@implementation UIImageView (WebCache)

- (void)sd_setImageWithURL:(NSURL *)url {
    [self sd_setImageWithURL:url placeholderImage:nil completed:nil];
}

- (void)sd_setImageWithURL:(NSURL *)url placeholderImage:(UIImage *)placeholder {
    [self sd_setImageWithURL:url placeholderImage:placeholder completed:nil];
}

- (void)sd_setImageWithURL:(NSURL *)url completed:(SDWebImageCompletionBlock)completedBlock {
    [self sd_setImageWithURL:url placeholderImage:nil completed:completedBlock];
}

- (void)sd_setImageWithURL:(NSURL *)url
          placeholderImage:(UIImage *)placeholder
                 completed:(SDWebImageCompletionBlock)completedBlock {
    [self sd_cancelCurrentImageLoad];

    objc_setAssociatedObject(self, kSDWebImageURLKey, url, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    if (placeholder != nil) {
        self.image = placeholder;
    }

    if (url == nil) {
        if (completedBlock) {
            NSError *error = [NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorBadURL userInfo:nil];
            completedBlock(nil, error, SDImageCacheTypeNone, nil);
        }
        return;
    }

    __weak typeof(self) weakSelf = self;
    id<SDWebImageOperation> operation = [[SDWebImageDownloader sharedDownloader]
                                         downloadImageWithURL:url
                                         options:0
                                         progress:nil
                                         completed:^(UIImage * _Nullable image, NSData * _Nullable data, NSError * _Nullable error, BOOL finished) {
        __strong typeof(weakSelf) strongSelf = weakSelf;
        if (!strongSelf) {
            return;
        }

        NSURL *currentURL = objc_getAssociatedObject(strongSelf, kSDWebImageURLKey);
        if (currentURL && ![currentURL isEqual:url]) {
            return;
        }

        if (image != nil) {
            strongSelf.image = image;
        }

        if (completedBlock) {
            completedBlock(image, error, SDImageCacheTypeNone, url);
        }
    }];

    objc_setAssociatedObject(self, kSDWebImageOperationKey, operation, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)sd_cancelCurrentImageLoad {
    id<SDWebImageOperation> operation = objc_getAssociatedObject(self, kSDWebImageOperationKey);
    [operation cancel];
    objc_setAssociatedObject(self, kSDWebImageOperationKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

@end

@implementation UIImage (SDGIF)
+ (UIImage *)sd_imageWithGIFData:(NSData *)data {
    if (data.length == 0) {
        return nil;
    }
    return [UIImage imageWithData:data];
}
@end
