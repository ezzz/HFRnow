#import <Foundation/Foundation.h>

@class ObjCTopicHTMLRenderContext;

@interface ObjCTopicHTMLRenderer : NSObject
- (NSString *)renderHTMLWithContext:(ObjCTopicHTMLRenderContext *)context;
@end
