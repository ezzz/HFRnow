//
//  SmileyCache.h
//  SuperHFRplus
//
//  Created by Bruno ARENE on 28/05/2020.
//

#ifndef SmileyCache_h
#define SmileyCache_h

#import <Foundation/Foundation.h>

@interface SmileyRequest : NSObject {
}

// TODO: add @property (nonatomic, strong) NSDate* dateLastRequest; 
@property (nonatomic, strong) NSString* sTextSmileys;
@property (nonatomic, strong) NSMutableArray* arrSmileys;

@end


@interface SmileyCache : NSObject {
}

@property (nonatomic, strong) NSMutableArray* arrCurrentSmileyArray;
@property (nonatomic, strong) NSMutableArray* arrCustomSmileys;
@property (nonatomic, strong) NSCache* cacheSmileys;
@property (nonatomic, strong) NSCache* cacheSmileysDefaults;
@property (nonatomic, strong) NSCache* cacheSmileyRequests;
@property BOOL bStopLoadingSmileysSearchToCache;
@property BOOL bStopLoadingSmileysCustomToCache;
@property BOOL bSearchSmileysActivated;
@property (nonatomic, strong) NSMutableArray *dicCommonSmileys;
@property (nonatomic, strong) NSMutableArray *dicSearchSmileys;

+ (SmileyCache *) shared;
- (void) handleSearchSmileyArray:(NSMutableArray*)arrSmileys forCollection:(UICollectionView*)cv spinner:(UIActivityIndicatorView*)spinner;
- (void) handleCustomSmileyArray:(NSMutableArray*)arrSmileys;
- (UIImage*) getImageDefaultSmileyForIndex:(int)index;
- (UIImage*) getImageForIndex:(int)index forCollection:(UICollectionView*)cv customSmiley:(BOOL)bCustomSmiley;
- (NSMutableArray*) getSmileyListForText:(NSString*)sTextSmileys;
- (NSString*) getSmileyCodeForIndex:(int)index;
- (NSString*) getSmileyImgUrlForIndex:(int)index;

@end


#endif /* SmileyCache_h */
