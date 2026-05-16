#import <Foundation/Foundation.h>

@class Forum;

@interface ObjCForumsLoaderWorker : NSObject

- (void)fetchContentWithCompletion:(void (^)(NSArray<Forum *> *forums, NSError *error))completion;
- (void)cancelFetchContent;

@end
