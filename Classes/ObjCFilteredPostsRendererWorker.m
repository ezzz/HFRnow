#import "ObjCFilteredPostsRendererWorker.h"

#import "ObjCMessageActionsBuilder.h"
#import "ObjCTopicHTMLRenderContext.h"
#import "ObjCTopicHTMLRenderer.h"
#import "ObjCTopicMessageContentBuilder.h"
#import "ObjCTopicMessageContentResult.h"
#import "ObjCTopicToolbarHTMLBuilder.h"
#import "Topic.h"

@implementation ObjCFilteredPostsRendererWorker

- (void)renderFilteredPosts:(NSArray *)items
                      topic:(Topic *)topic
                  startPage:(NSNumber *)startPage
                    endPage:(NSNumber *)endPage
                   finished:(NSNumber *)finished
                 completion:(void (^)(NSString *, NSDictionary<NSNumber *,NSDictionary<NSString *,NSString *> *> *, NSError *))completion {
    if (!completion) {
        return;
    }
    if (!topic) {
        NSError *error = [NSError errorWithDomain:@"ObjCFilteredPostsRendererWorker"
                                             code:-1
                                         userInfo:@{NSLocalizedDescriptionKey: @"Topic invalide."}];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, nil, error);
        });
        return;
    }

    NSArray *safeItems = items ?: @[];
    NSString *currentURL = topic.aURL ?: topic.aURLOfLastPage ?: topic.aURLOfFirstPage ?: @"";
    NSDictionary *inputData = @{
        @"post": topic.postID > 0 ? [NSString stringWithFormat:@"%d", topic.postID] : @"",
        @"cat": topic.catID > 0 ? [NSString stringWithFormat:@"%d", topic.catID] : @""
    };
    BOOL isPrivateCategory = [inputData[@"cat"] isEqualToString:@"prive"];
    ObjCTopicMessageContentResult *content = [[[ObjCTopicMessageContentBuilder alloc] init]
        buildContentForItems:safeItems
               currentAnchor:@""
          separatorRequested:NO
           isPrivateCategory:isPrivateCategory];
    NSString *toolbarHTML = [[[ObjCTopicToolbarHTMLBuilder alloc] init]
        toolbarHTMLWithBeginEnabled:NO
                         endEnabled:NO
                         pageNumber:0
                     lastPageNumber:0
                       searchActive:NO
               hasMoreFilteredPosts:![finished boolValue]];
    ObjCTopicHTMLRenderContext *context = [[ObjCTopicHTMLRenderContext alloc] init];
    context.messagesHTML = content.messagesHTML ?: @"";
    context.toolbarHTML = toolbarHTML;
    context.refreshButtonHTML = @"";
    context.customFontSizeCSS = @"";
    context.searchActive = NO;
    NSString *html = [[[ObjCTopicHTMLRenderer alloc] init] renderHTMLWithContext:context];
    NSDictionary *actions = [[[ObjCMessageActionsBuilder alloc] init]
        actionsByIndexForItems:safeItems
                     inputData:inputData
                     topicName:topic.aTitle ?: topic._aTitle ?: @""
                    currentURL:currentURL
                 canBeFavorite:YES];
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(html, actions, nil);
    });
}

@end
