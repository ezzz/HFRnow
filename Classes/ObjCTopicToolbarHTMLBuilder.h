#import <Foundation/Foundation.h>

@interface ObjCTopicToolbarHTMLBuilder : NSObject

- (NSString *)toolbarHTMLWithBeginEnabled:(BOOL)beginEnabled
                               endEnabled:(BOOL)endEnabled
                               pageNumber:(NSInteger)pageNumber
                           lastPageNumber:(NSInteger)lastPageNumber
                             searchActive:(BOOL)searchActive
                     hasMoreFilteredPosts:(BOOL)hasMoreFilteredPosts;

@end
