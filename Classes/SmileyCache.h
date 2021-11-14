//
//  SmileyCache.h
//  SuperHFRplus
//
//  Created by Bruno ARENE on 28/05/2020.
//

#ifndef SmileyCache_h
#define SmileyCache_h

#import <Foundation/Foundation.h>

typedef enum {
    ArraySmileysDefault           = 0,
    ArraySmileysSearch            = 1,
    ArraySmileysFavorites         = 2,
} SmileArrayEnum;

@interface SmileyRequest : NSObject {
}

// TODO: add @property (nonatomic, strong) NSDate* dateLastRequest; 
@property (nonatomic, strong) NSString* sTextSmileys;
@property (nonatomic, strong) NSMutableArray* arrSmileys;

@end

@interface ImageInCache : NSObject<NSDiscardableContent>
@property (nonatomic, strong) UIImage* image;

@end

@interface SmileyFavorite : NSObject<NSCoding>
{
}

@property (nonatomic, strong) NSString *sCode;
@property (nonatomic, strong) NSString *sRawUrl;
@property (nonatomic, strong) NSDate   *dateAdded;

@end

@interface SmileyCache : NSObject {
}

@property (nonatomic, strong) NSMutableArray* arrCurrentSmileyArray;
@property (nonatomic, strong) NSMutableArray* arrFavoritesSmileysApp;
@property (nonatomic, strong) NSMutableArray* arrFavoritesSmileysForum;
@property (nonatomic, strong) NSCache* cacheSmileys;
@property (nonatomic, strong) NSCache* cacheSmileysDefaults;
@property (nonatomic, strong) NSCache* cacheSmileyRequests;
@property BOOL bStopLoadingSmileysSearchToCache;
@property BOOL bStopLoadingSmileysFavoritesToCache;
@property BOOL bStopLoadingSmileysCustomToCache;
@property BOOL bSearchSmileysActivated;
@property (nonatomic, strong) NSMutableArray *dicCommonSmileys;
@property (nonatomic, strong) NSMutableArray *dicSearchSmileys;
@property (nonatomic, strong) NSMutableDictionary *dicFavoritesSmileys;
@property int iNbFailuresLoadingSmileys;
+ (SmileyCache *) shared;
- (void) handleSearchSmileyArray:(NSMutableArray*)arrSmileys forCollection:(UICollectionView*)cv spinner:(UIActivityIndicatorView*)spinner;
- (void) handleCustomSmileyArray:(NSMutableArray*)arrSmileys forCollection:(UICollectionView*)cv;
- (UIImage*) getImageDefaultSmileyForIndex:(int)index;
- (UIImage*) getImageForIndex:(int)index forCollection:(UICollectionView*)cv andIndexPath:(NSIndexPath*)ip customSmiley:(SmileArrayEnum)eSmileyArrayType;
- (NSMutableArray*) getSmileyListForText:(NSString*)sTextSmileys;
- (NSString*) getSmileyCodeForIndex:(int)index bCustom:(BOOL)bCustom;
- (NSString*) getSmileyImgUrlForIndex:(int)index bCustom:(BOOL)bCustom;
- (BOOL)AddAndSaveDicFavorites:(NSString*)sCode source:(NSString*)sSource addSmiley:(BOOL)bAdd;
- (BOOL)isFavoriteSmileyFromApp:(NSString*)sCode;
- (BOOL)isFavoriteSmileyFromForum:(NSString*)sCode
;
@end


#endif /* SmileyCache_h */
