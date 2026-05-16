#import <Foundation/Foundation.h>

@class Forum;

@interface ObjCForumsParser : NSObject

- (NSArray<Forum *> *)parseForumsFromData:(NSData *)contentData;

@end
