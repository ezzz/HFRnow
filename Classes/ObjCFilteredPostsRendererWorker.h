#import <Foundation/Foundation.h>

@class Topic;

@interface ObjCFilteredPostsRendererWorker : NSObject

- (void)renderFilteredPosts:(NSArray *)items
                      topic:(Topic *)topic
                  startPage:(NSNumber *)startPage
                    endPage:(NSNumber *)endPage
                   finished:(NSNumber *)finished
                 completion:(void (^)(NSString *html, NSDictionary<NSNumber *, NSDictionary<NSString *, NSString *> *> *messageActionsByIndex, NSError *error))completion;

@end
