//
//  Favorite.h
//  HFRplus
//
//  Created by FLK on 21/07/12.
//

#import <Foundation/Foundation.h>
@class Forum;
@class HTMLNode;
@class Topic;

NS_ASSUME_NONNULL_BEGIN

@interface Favorite : NSObject

@property (nonatomic, strong, nullable) Forum *forum;
@property (nonatomic, strong) NSMutableArray<Topic *> *topics;
@property (nonatomic, strong, nullable) NSNumber *order;

- (void)parseNode:(HTMLNode *)node;
- (nullable id)addTopicWithNode:(HTMLNode *)node;

@end

NS_ASSUME_NONNULL_END
