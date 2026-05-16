#import <Foundation/Foundation.h>

@class ObjCTopicMessageContentResult;

@interface ObjCTopicMessageContentBuilder : NSObject

- (ObjCTopicMessageContentResult *)buildContentForItems:(NSArray *)items
                                           currentAnchor:(NSString *)currentAnchor
                                      separatorRequested:(BOOL)separatorRequested
                                       isPrivateCategory:(BOOL)isPrivateCategory;

@end
