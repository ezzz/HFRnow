#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SDImageCacheType) {
    SDImageCacheTypeNone,
    SDImageCacheTypeDisk,
    SDImageCacheTypeMemory
};

@protocol SDWebImageOperation <NSObject>
- (void)cancel;
@end

typedef NS_OPTIONS(NSUInteger, SDWebImageDownloaderOptions) {
    SDWebImageDownloaderLowPriority = 1 << 0,
    SDWebImageDownloaderProgressiveDownload = 1 << 1,
    SDWebImageDownloaderUseNSURLCache = 1 << 2,
    SDWebImageDownloaderIgnoreCachedResponse = 1 << 3,
    SDWebImageDownloaderContinueInBackground = 1 << 4,
    SDWebImageDownloaderHandleCookies = 1 << 5,
    SDWebImageDownloaderAllowInvalidSSLCertificates = 1 << 6,
    SDWebImageDownloaderHighPriority = 1 << 7,
};

typedef void(^SDWebImageDownloaderProgressBlock)(NSInteger receivedSize, NSInteger expectedSize, NSURL * _Nullable targetURL);
typedef void(^SDWebImageDownloaderCompletedBlock)(UIImage * _Nullable image, NSData * _Nullable data, NSError * _Nullable error, BOOL finished);
typedef void(^SDWebImageCompletionBlock)(UIImage * _Nullable image, NSError * _Nullable error, SDImageCacheType cacheType, NSURL * _Nullable imageURL);

@interface SDImageCache : NSObject
+ (instancetype)sharedImageCache;
- (void)clearMemory;
@end

@interface SDWebImageDownloader : NSObject
+ (instancetype)sharedDownloader;
- (nullable id<SDWebImageOperation>)downloadImageWithURL:(nullable NSURL *)url
                                                 options:(SDWebImageDownloaderOptions)options
                                                progress:(nullable SDWebImageDownloaderProgressBlock)progressBlock
                                               completed:(nullable SDWebImageDownloaderCompletedBlock)completedBlock;
@end

@interface UIImageView (WebCache)
- (void)sd_setImageWithURL:(nullable NSURL *)url;
- (void)sd_setImageWithURL:(nullable NSURL *)url placeholderImage:(nullable UIImage *)placeholder;
- (void)sd_setImageWithURL:(nullable NSURL *)url completed:(nullable SDWebImageCompletionBlock)completedBlock;
- (void)sd_setImageWithURL:(nullable NSURL *)url
          placeholderImage:(nullable UIImage *)placeholder
                 completed:(nullable SDWebImageCompletionBlock)completedBlock;
- (void)sd_cancelCurrentImageLoad;
@end

@interface UIImage (SDGIF)
+ (nullable UIImage *)sd_imageWithGIFData:(nullable NSData *)data;
@end

NS_ASSUME_NONNULL_END
