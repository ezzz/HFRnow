#import "ObjCForumsLoaderWorker.h"

#import "ASIHTTPRequest+Tools.h"
#import "Constants.h"
#import "Forum.h"
#import "ObjCForumsParser.h"
#import "k.h"

@interface ObjCForumsLoaderWorker ()
@property (nonatomic, strong) ASIHTTPRequest *request;
@property (nonatomic, copy) void (^completion)(NSArray<Forum *> *, NSError *);
@end

@implementation ObjCForumsLoaderWorker

- (void)fetchContentWithCompletion:(void (^)(NSArray<Forum *> *, NSError *))completion {
    [self cancelFetchContent];
    self.completion = completion;
    [ASIHTTPRequest setDefaultTimeOutSeconds:kTimeoutMini];
    ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:[k ForumURL]]];
    self.request = request;
    __weak typeof(self) weakSelf = self;
    __weak ASIHTTPRequest *weakRequest = request;
    [request setCompletionBlock:^{
        __strong typeof(weakSelf) self = weakSelf;
        ASIHTTPRequest *strongRequest = weakRequest;
        if (!self || strongRequest != self.request) return;
        NSArray<Forum *> *forums = [[[ObjCForumsParser alloc] init] parseForumsFromData:[strongRequest safeResponseData]];
        [self finishWithForums:forums error:nil];
    }];
    [request setFailedBlock:^{
        __strong typeof(weakSelf) self = weakSelf;
        ASIHTTPRequest *strongRequest = weakRequest;
        if (!self || strongRequest != self.request) return;
        NSError *error = strongRequest.error ?: [NSError errorWithDomain:@"ObjCForumsLoaderWorker" code:-1 userInfo:nil];
        [self finishWithForums:@[] error:error];
    }];
    [request startAsynchronous];
}

- (void)cancelFetchContent {
    [self.request cancel];
    self.request = nil;
}

- (void)finishWithForums:(NSArray<Forum *> *)forums error:(NSError *)error {
    void (^completion)(NSArray<Forum *> *, NSError *) = self.completion;
    self.completion = nil;
    self.request = nil;
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(forums, error);
    });
}

@end
