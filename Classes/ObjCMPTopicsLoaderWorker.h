#import "ObjCForumTopicsLoaderWorker.h"

@interface ObjCMPTopicsLoaderWorker : ObjCForumTopicsLoaderWorker

- (void)fetchContentWithCompletion:(void (^)(NSArray<Topic *> *topics, NSError *error))completion;

@end
