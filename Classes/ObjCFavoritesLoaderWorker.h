//
//  ObjCFavoritesLoaderWorker.h
//  HFRplus
//

#import <Foundation/Foundation.h>

@class ASIHTTPRequest, Favorite;

@interface ObjCFavoritesLoaderWorker : NSObject

@property (nonatomic, copy) void (^completion)(NSArray<Favorite *> *favorites, NSError *error);
@property (nonatomic, strong) ASIHTTPRequest *request;

- (void)fetchContentWithCompletion:(void (^)(NSArray<Favorite *> *favorites, NSError *error))completion;
- (void)cancelFetchContent;

@end
