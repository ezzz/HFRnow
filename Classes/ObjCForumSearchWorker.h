#import "ObjCForumTopicsLoaderWorker.h"

@interface ObjCForumSearchWorker : ObjCForumTopicsLoaderWorker

- (void)performForumSearchWithParams:(NSDictionary *)params
                           completion:(void (^)(NSArray<Topic *> *topics, NSDictionary *pageInfo, NSError *error))completion;
- (void)fetchForumSearchPageURL:(NSString *)urlString
                     completion:(void (^)(NSArray<Topic *> *topics, NSDictionary *pageInfo, NSError *error))completion;
- (void)cancelForumSearch;

@end
