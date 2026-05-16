#import <Foundation/Foundation.h>

@interface ObjCMessageActionsBuilder : NSObject

- (NSDictionary<NSNumber *, NSDictionary<NSString *, NSString *> *> *)actionsByIndexForItems:(NSArray *)items
                                                                                   inputData:(NSDictionary<NSString *, NSString *> *)inputData
                                                                                   topicName:(NSString *)topicName
                                                                                  currentURL:(NSString *)currentURL
                                                                               canBeFavorite:(BOOL)canBeFavorite;

@end
