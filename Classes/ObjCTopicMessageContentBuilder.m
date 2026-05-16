#import "ObjCTopicMessageContentBuilder.h"

#import "LinkItem.h"
#import "ObjCTopicMessageContentResult.h"

@implementation ObjCTopicMessageContentBuilder

- (ObjCTopicMessageContentResult *)buildContentForItems:(NSArray *)items
                                           currentAnchor:(NSString *)currentAnchor
                                      separatorRequested:(BOOL)separatorRequested
                                       isPrivateCategory:(BOOL)isPrivateCategory {
    ObjCTopicMessageContentResult *result = [[ObjCTopicMessageContentResult alloc] init];
    NSMutableString *html = [NSMutableString string];
    NSCharacterSet *nonDigits = NSCharacterSet.decimalDigitCharacterSet.invertedSet;
    int currentFlagValue = [[currentAnchor stringByTrimmingCharactersInSet:nonDigits] intValue];
    BOOL foundCurrentFlag = currentFlagValue == 0;
    int closePostID = 0;

    for (NSUInteger index = 0; index < items.count; index++) {
        id candidate = items[index];
        if (![candidate isKindOfClass:LinkItem.class]) {
            continue;
        }
        LinkItem *item = candidate;
        [html appendString:[item toHTML:(int)index isMP:!isPrivateCategory]];

        if (!foundCurrentFlag) {
            int candidatePostID = [[item.postID stringByTrimmingCharactersInSet:nonDigits] intValue];
            if (candidatePostID == currentFlagValue) {
                if (separatorRequested && index < items.count - 1) {
                    [html appendString:@"<div class=\"separator1\"></div>"];
                }
                foundCurrentFlag = YES;
                closePostID = candidatePostID;
            }
            if (closePostID && currentFlagValue && candidatePostID >= currentFlagValue) {
                closePostID = candidatePostID;
                foundCurrentFlag = YES;
            } else {
                closePostID = candidatePostID;
            }
        }
    }

    result.messagesHTML = [html copy];
    result.resolvedAnchor = closePostID > 0 ? [NSString stringWithFormat:@"#t%d", closePostID] : currentAnchor;
    return result;
}

@end
