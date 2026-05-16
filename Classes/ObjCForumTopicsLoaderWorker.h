#import "ObjCTopicListLoaderWorkerBase.h"

@class Forum;
@class Topic;

@interface ObjCForumTopicsLoaderWorker : ObjCTopicListLoaderWorkerBase

@property (nonatomic, copy) void (^completion)(NSArray<Topic *> *topics, NSError *error);

- (void)fetchContentForForum:(Forum *)forum
                   flagIndex:(NSInteger)flagIndex
                     pageURL:(NSString *)pageURL
                  completion:(void (^)(NSArray<Topic *> *topics, NSError *error))completion;

@end
