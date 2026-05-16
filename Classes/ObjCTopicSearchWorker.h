#import <Foundation/Foundation.h>

@interface ObjCTopicSearchWorker : NSObject

- (void)performTopicSearchWithParams:(NSDictionary<NSString *, NSString *> *)params
                          completion:(void (^)(NSString *resultURL, NSError *error))completion;

@end
