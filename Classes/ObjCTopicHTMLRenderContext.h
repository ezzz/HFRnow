#import <Foundation/Foundation.h>

@interface ObjCTopicHTMLRenderContext : NSObject
@property (nonatomic, copy) NSString *messagesHTML;
@property (nonatomic, copy) NSString *refreshButtonHTML;
@property (nonatomic, copy) NSString *toolbarHTML;
@property (nonatomic, copy) NSString *customFontSizeCSS;
@property (nonatomic, assign) BOOL searchActive;
@end
