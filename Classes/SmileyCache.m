//
//  SmileyCache.m
//  SuperHFRplus
//
//
//  Created by ezzz on 2020.
//

#import <Foundation/Foundation.h>
#import "ASIHTTPRequest+Tools.h"
#import "SmileyCache.h"
#import "OfflineTableViewController.h"
#import "HTMLparser.h"
#import "Constants.h"
#import <SDWebImage/SDWebImage.h>

#define IMAGE_CACHE_MAX_ELEMENTS 1000
#define IMAGE_CACHE_SMILEYS_DEFAULTS_MAX_ELEMENTS 50
#define SMILEY_CACHE_FAVORITES_DIC @"smiley_favorites_cache2"
#define NOT_FOUND -1

@implementation SmileyRequest
@end

@implementation SmileyFavorite

- (void)encodeWithCoder:(NSCoder *)encoder {
    [encoder encodeObject:self.sCode forKey:@"sCode"];
    [encoder encodeObject:self.sRawUrl forKey:@"sRawUrl"];
    [encoder encodeObject:self.dateAdded forKey:@"dateAdded"];
}

- (id)initWithCoder:(NSCoder *)decoder {
    self = [super init];
    if (self) {
        self.sCode = [decoder decodeObjectForKey:@"sCode"];
        self.sRawUrl = [decoder decodeObjectForKey:@"sRawUrl"];
        self.dateAdded = [decoder decodeObjectForKey:@"dateAdded"];
    }
    return self;
}
@end

@implementation ImageInCache
@synthesize image;

- (BOOL)beginContentAccess {
    if (!self.image)
        return NO;
    return YES;
}

- (void)endContentAccess {
}

- (void)discardContentIfPossible {
    self.image = nil;
}

- (BOOL)isContentDiscarded {
    return self.image == nil;
}
@end

@implementation SmileyCache

@synthesize arrCurrentSmileyArray, cacheSmileys, cacheSmileysDefaults, bStopLoadingSmileysSearchToCache, bStopLoadingSmileysCustomToCache, dicCommonSmileys, dicSearchSmileys, bSearchSmileysActivated;

static SmileyCache *_shared = nil;    // static instance variable

+ (SmileyCache *)shared {
    if (_shared == nil) {
        _shared = [[super allocWithZone:NULL] init];
    }
    return _shared;
}

- (id)init {
    if ( (self = [super init]) ) {
        // your custom initialization
        self.arrCurrentSmileyArray = nil;
        self.cacheSmileys = [[NSCache alloc] init];
        self.cacheSmileys.countLimit = IMAGE_CACHE_MAX_ELEMENTS;
        self.cacheSmileysDefaults = [[NSCache alloc] init];
        self.cacheSmileysDefaults.countLimit = IMAGE_CACHE_SMILEYS_DEFAULTS_MAX_ELEMENTS;
        self.bStopLoadingSmileysSearchToCache = NO;
        self.bStopLoadingSmileysCustomToCache = NO;
        self.bSearchSmileysActivated = NO;
        NSString *plistPath = [[NSBundle mainBundle] pathForResource:@"commonsmile" ofType:@"plist"];
        NSMutableArray* arr = [NSMutableArray arrayWithContentsOfFile:plistPath];
        self.dicCommonSmileys = [[NSMutableArray alloc] init];
        for (int index = 0; index < arr.count; index++) {
            NSNumber* n =  arr[index][@"editor"];
            int i = [n intValue];
            if (i == 1) {
                [self.dicCommonSmileys addObject:arr[index]];
            }
            else {
                //NSLog(@"index %ld not imported", (long)index);
            }
        }
        [self loadDicFavorties];
    }
    return self;
}

- (void)handleSearchSmileyArray:(NSMutableArray*)arrSmileys forCollection:(UICollectionView*)cv spinner:(UIActivityIndicatorView*)spinner
{
    self.bStopLoadingSmileysSearchToCache = NO;
    self.bSearchSmileysActivated = YES;
    self.arrCurrentSmileyArray = [arrSmileys mutableCopy];
    dispatch_async(dispatch_get_main_queue(), ^{
        [cv reloadData];
    });

    BOOL bHasbeenReloaded = NO;
    for (int i = 0; i < self.arrCurrentSmileyArray.count; i++) {
        NSString *filename = [[[self.arrCurrentSmileyArray objectAtIndex:i] objectForKey:@"source"] stringByReplacingOccurrencesOfString:@"http://forum-images.hardware.fr/" withString:@""];
        filename = [filename stringByReplacingOccurrencesOfString:@"https://forum-images.hardware.fr/" withString:@""];
        
        NSLog(@"URL search: %@ ", [NSString stringWithFormat:@"%@", [[self.arrCurrentSmileyArray objectAtIndex:i] objectForKey:@"source"]]);

        NSData* imgData = [NSData dataWithContentsOfURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@", [[[self.arrCurrentSmileyArray objectAtIndex:i] objectForKey:@"source"] stringByAddingPercentEscapesUsingEncoding:NSASCIIStringEncoding]]]];
        //UIImage *image = [UIImage imageWithData:imgData];sd_animatedGIFWithData
        if (imgData) {
            UIImage *image = [UIImage sd_imageWithGIFData:imgData];
            
            if (image != nil) {
                //NSLog(@"SmileyCache2 ADD: %@",filename);
                ImageInCache* iic = [[ImageInCache alloc] init];
                iic.image = image;
                [self.cacheSmileys setObject:iic forKey:filename];
            }
        }
        else {
            NSLog(@"Image ERROOOR loading (%d) : %@", i, filename);
        }

        // Says VC that cell can be reloaded
        dispatch_async(dispatch_get_main_queue(), ^{
            //[cv reloadData];
            NSIndexPath* ip = [NSIndexPath indexPathForRow:i inSection:0];
            NSArray *myArray = [[NSArray alloc] initWithObjects:ip, nil];
            [cv reloadItemsAtIndexPaths:myArray];
        });

        if (self.bStopLoadingSmileysSearchToCache) {
            NSLog(@"### STOPPED LOADING SMILEYS");
            break;
        }
     }
    self.bStopLoadingSmileysSearchToCache = YES;
    NSLog(@"Finished loading all smileys");
    if (!bHasbeenReloaded) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [spinner stopAnimating];
            [cv reloadData];
        });
    }
}

- (void)handleCustomSmileyArray:(NSMutableArray*)arrSmileys forCollection:(UICollectionView*)cv 
{
    self.bStopLoadingSmileysCustomToCache = NO;
    
    // For storage
    self.arrFavoritesSmileysForum = [arrSmileys mutableCopy];

    [self loadFavoriteSmileyArr:self.arrFavoritesSmileysForum forCollection:cv];
    [self loadFavoriteSmileyArr:self.arrFavoritesSmileysApp forCollection:cv];
    
    self.bStopLoadingSmileysCustomToCache = YES;
    NSLog(@"Finished loading all smileys");
}

- (void)loadFavoriteSmileyArr:(NSMutableArray*)arrSmileyFavorite forCollection:(UICollectionView*)cv
{
    for (int i = 0; i < arrSmileyFavorite.count; i++) {
        NSString *filename = [[[arrSmileyFavorite objectAtIndex:i] objectForKey:@"source"] stringByReplacingOccurrencesOfString:@"http://forum-images.hardware.fr/" withString:@""];
        filename = [filename stringByReplacingOccurrencesOfString:@"https://forum-images.hardware.fr/" withString:@""];

        //NSLog(@"URL custom: %@ ", [NSString stringWithFormat:@"%@", [[self.arrCustomSmileys objectAtIndex:i] objectForKey:@"source"]]);

        NSData* imgData = [NSData dataWithContentsOfURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@", [[[arrSmileyFavorite objectAtIndex:i] objectForKey:@"source"] stringByAddingPercentEscapesUsingEncoding:NSASCIIStringEncoding]]]];

        if (imgData) {
            UIImage *image = [UIImage sd_imageWithGIFData:imgData];
            if (image != nil) {
                NSLog(@"SmileyCache3 ADD: %@",filename);
                ImageInCache* iic = [[ImageInCache alloc] init];
                iic.image = image;
                [self.cacheSmileys setObject:iic forKey:filename];
            }
        }
        else {
            NSLog(@"Image ERROOOR loading (%d) : %@", i, filename);
        }
        
        // Says VC that cell can be reloaded
        dispatch_async(dispatch_get_main_queue(), ^{
            //[cv reloadData];
            NSIndexPath* ip = [NSIndexPath indexPathForRow:i inSection:0];
            NSArray *myArray = [[NSArray alloc] initWithObjects:ip, nil];
            [cv reloadItemsAtIndexPaths:myArray];
        });

        if (self.bStopLoadingSmileysCustomToCache) {
            NSLog(@"### STOPPED LOADING CUSTOM SMILEYS");
            break;
        }
     }
}

- (UIImage*) getImageForIndex:(int)index forCollection:(UICollectionView*)cv andIndexPath:(NSIndexPath*)ip favoriteSmiley:(BOOL)bFavoriteSmiley favoriteFromApp:(BOOL)bFavoriteFromApp
{
    NSString *filename = nil;

    if (bFavoriteSmiley && bFavoriteFromApp) {
        filename = [[[self.arrFavoritesSmileysApp objectAtIndex:index] objectForKey:@"source"] stringByReplacingOccurrencesOfString:@"http://forum-images.hardware.fr/" withString:@""];
        NSLog(@"Searching image App Favorite index (%d)", index);
    }
    else if (bFavoriteSmiley) {
        filename = [[[self.arrFavoritesSmileysForum objectAtIndex:index] objectForKey:@"source"] stringByReplacingOccurrencesOfString:@"http://forum-images.hardware.fr/" withString:@""];
        NSLog(@"Searching image Forum Favorite index (%d)", index);
    }
    else {
        filename = [[[self.arrCurrentSmileyArray objectAtIndex:index] objectForKey:@"source"] stringByReplacingOccurrencesOfString:@"http://forum-images.hardware.fr/" withString:@""];
        NSLog(@"Searching image Current index (%d)", index);
    }
    filename = [filename stringByReplacingOccurrencesOfString:@"https://forum-images.hardware.fr/" withString:@""];
    UIImage* image = nil;
    ImageInCache* iic = [self.cacheSmileys objectForKey:filename];
    if (iic) {
        image = iic.image;
    }
    
    if (image == nil && ((!bFavoriteSmiley && self.bStopLoadingSmileysSearchToCache) || (bFavoriteSmiley && self.bStopLoadingSmileysCustomToCache)))
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
            NSString* source = nil;
            if (bFavoriteSmiley && bFavoriteFromApp) {
                int indexFavApp = (int)index - (int)self.arrFavoritesSmileysForum.count;
                source  = [[self.arrFavoritesSmileysApp objectAtIndex:indexFavApp] objectForKey:@"source"];
                NSLog(@"--> Loading image FavoriteApp at index (%d) : %@", index, filename);
            }
            else if (bFavoriteSmiley) {
                source  = [[self.arrFavoritesSmileysForum objectAtIndex:index] objectForKey:@"source"];
                NSLog(@"--> Loading image FavoriteForum at index (%d) : %@", index, filename);
            }
            else {
                if (index < self.arrCurrentSmileyArray.count) {
                    source  = [[self.arrCurrentSmileyArray objectAtIndex:index] objectForKey:@"source"];
                    NSLog(@"--> Loading image Search at index (%d) : %@", index, filename);
                }
            }
            
            if (source) {
                NSString* sourceConv1 = [source stringByAddingPercentEscapesUsingEncoding:NSASCIIStringEncoding];
                NSData* imgData = [NSData dataWithContentsOfURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@", sourceConv1]]];
                
                
                if (imgData) {
                    UIImage* image = [UIImage sd_imageWithGIFData:imgData];
                    ImageInCache* iic = [[ImageInCache alloc] init];
                    iic.image = image;
                    //NSLog(@"SmileyCache1 ADD: %@",filename);
                    [self.cacheSmileys setObject:iic forKey:filename];
                

                    // Says VC that cell can be reloaded
                    dispatch_async(dispatch_get_main_queue(), ^{
                        //[cv reloadData];
                        NSArray *myArray = [[NSArray alloc] initWithObjects:ip, nil];
                        //NSLog(@"SmileyCache1 RELOAD cell: %d", (int)ip.row);
                        [cv reloadItemsAtIndexPaths:myArray];
                    });
                }
            }
        });
    }
    else {
        NSLog(@"--> Image in cache");
    }
    return image;
}



- (UIImage*) getImageDefaultSmileyForIndex:(int)index
{
    NSString *filename = [self.dicCommonSmileys[index][@"resource"] stringByReplacingOccurrencesOfString:@"http://forum-images.hardware.fr/" withString:@""];
    UIImage* image = [self.cacheSmileysDefaults objectForKey:filename];
    if (image == nil) {
        NSString *filenameShort = [filename stringByDeletingPathExtension];
        NSString* filepath = [[NSBundle mainBundle] pathForResource:filenameShort ofType:@"gif"];
        NSData* imgData = [NSData dataWithContentsOfFile:filepath];
        image = [UIImage sd_imageWithGIFData:imgData];
        //NSLog(@"%@ size : (%f) %f x %f", filename, image.scale, image.size.width, image.size.height);
        [self.cacheSmileysDefaults setObject:image forKey:filename];
    }
    return image;
}

- (NSString*) getSmileyCodeForIndex:(int)index favoriteSmiley:(BOOL)bFavoriteSmiley favoriteFromApp:(BOOL)bFavoriteFromApp
{
    if (bFavoriteSmiley && bFavoriteFromApp) {
        return [[self.arrFavoritesSmileysApp objectAtIndex:index] objectForKey:@"code"];
    }
    else if (bFavoriteSmiley) {
        return [[self.arrFavoritesSmileysForum objectAtIndex:index] objectForKey:@"code"];
    }
    else {
        return [[self.arrCurrentSmileyArray objectAtIndex:index] objectForKey:@"code"];
    }
}
- (NSString*) getSmileyImgUrlForIndex:(int)index favoriteSmiley:(BOOL)bFavoriteSmiley favoriteFromApp:(BOOL)bFavoriteFromApp
{
    if (bFavoriteSmiley && bFavoriteFromApp) {
        return [[self.arrFavoritesSmileysApp objectAtIndex:index] objectForKey:@"source"];
    }
    else if (bFavoriteSmiley) {
        return [[self.arrFavoritesSmileysForum objectAtIndex:index] objectForKey:@"source"];
    }
    else {
        return [[self.arrCurrentSmileyArray objectAtIndex:index] objectForKey:@"source"];
    }
}

- (NSDate*) getFavoriteSmileyDateForIndex:(int)index
{
    NSDate* d = [[self.arrFavoritesSmileysApp objectAtIndex:index] objectForKey:@"date"];
    if (d == nil) {
        return [NSDate now];
    }
    return d;
}

- (NSMutableArray*) getSmileyListForText:(NSString*)sTextSmileys
{
    NSMutableArray* arr = [self.cacheSmileyRequests objectForKey:sTextSmileys];
    NSLog(@"getSmileyListForText %@", arr);
    return arr;
}


- (void)loadDicFavorties {
    // In worse case, take what is present in cache
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    NSString *directory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    NSString *filename = [[NSString alloc] initWithString:[directory stringByAppendingPathComponent:SMILEY_CACHE_FAVORITES_DIC]];

    if ([fileManager fileExistsAtPath:filename]) {
        NSData *data = [[NSData alloc] initWithContentsOfFile:filename];
        NSKeyedUnarchiver *unarchiver = [[NSKeyedUnarchiver alloc] initForReadingWithData:data];// error:&error];
        self.dicFavoritesSmileys = [unarchiver decodeObject];
        [unarchiver finishDecoding];
        [self.dicFavoritesSmileys enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL* stop) {
            NSLog(@"Full list dicFavoritesSmileys :  %@ => %@ / %@", key, ((SmileyFavorite*)value).sCode, ((SmileyFavorite*)value).dateAdded);
        }];
    }
    else {
        self.dicFavoritesSmileys = [[NSMutableDictionary alloc] init];
    }
    
    // Adding favorites smileys to favorites smileys
    self.arrFavoritesSmileysApp = [[NSMutableArray alloc] init];
    NSArray *myArray = [self.dicFavoritesSmileys keysSortedByValueUsingComparator: ^(SmileyFavorite* sf1, SmileyFavorite* sf2) {
        if ([sf1.dateAdded timeIntervalSinceDate:sf2.dateAdded] > 0) {
            return (NSComparisonResult)NSOrderedDescending;
        }
        else if ([sf1.dateAdded timeIntervalSinceDate:sf2.dateAdded] < 0) {
            return (NSComparisonResult)NSOrderedAscending;
        }
        return (NSComparisonResult)NSOrderedSame;
    }];
    
    for (NSString *key in myArray) {
        SmileyFavorite* sf = [self.dicFavoritesSmileys objectForKey:key];
        NSLog(@"Adding dicFavoritesSmileys :  %@ => %@", sf.sCode, sf.sRawUrl);
        [self.arrFavoritesSmileysApp addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:sf.sRawUrl, sf.sCode, nil] forKeys:[NSArray arrayWithObjects:@"source", @"code", nil]]];
    }
}

- (BOOL)AddAndSaveDicFavoritesApp:(NSString*)sCode source:(NSString*)sRawUrl addSmiley:(BOOL)bAdd {
    NSString *directory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    NSString *filename = [[NSString alloc] initWithString:[directory stringByAppendingPathComponent:SMILEY_CACHE_FAVORITES_DIC]];
    
    NSMutableData *data = [[NSMutableData alloc] init];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];// error:&error];
    BOOL bShouldSaveToFile = YES;
    if (bAdd) {
        NSLog(@"Adding dicFavoritesSmileys :  %@ => %@", sCode, sRawUrl);
        //if ([self findCustomSmileyIndex:sCode] > NOT_FOUND) {
        if ([self.dicFavoritesSmileys objectForKey:sCode]) {
            return NO;
        }
        SmileyFavorite* sf = [[SmileyFavorite alloc] init];
        sf.sCode = sCode;
        sf.sRawUrl = sRawUrl;
        sf.dateAdded = [NSDate now];
        // dicFavoritesSmileys is used for persistency
        [self.dicFavoritesSmileys setObject:sf forKey:sCode];
        
        // arrCustomSmileys is used for display and is merged with the personnal
        [self.arrFavoritesSmileysApp addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:sRawUrl, sCode, nil] forKeys:[NSArray arrayWithObjects:@"source", @"code", nil]]];
    }
    else {
        NSLog(@"Removing dicFavoritesSmileys :  %@ => %@", sCode, sRawUrl);
        if ([self.dicFavoritesSmileys objectForKey:sCode]) {
            [self.dicFavoritesSmileys removeObjectForKey:sCode];
            
            // Remove from arrFavoritesSmileysApp
            int index = -1;
            for (int i = 0; i < self.arrFavoritesSmileysApp.count; i++) {
                if ([[[self.arrFavoritesSmileysApp objectAtIndex:i] objectForKey:@"code"] isEqualToString:sCode]) {
                    index = i;
                    break;
                }
            }
            if (index >= 0) {
                [self.arrFavoritesSmileysApp removeObjectAtIndex:index];
            }
            bShouldSaveToFile = YES;
        }
        else {
            return NO;
        }
    }
    if (bShouldSaveToFile) {
        [self.dicFavoritesSmileys enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL* stop) {
          NSLog(@"Full list dicFavoritesSmileys :  %@ => %@ / %@", key, ((SmileyFavorite*)value).sCode, ((SmileyFavorite*)value).dateAdded);
        }];
        [archiver encodeObject:self.dicFavoritesSmileys];
        [archiver finishEncoding];
        return [data writeToFile:filename atomically:YES];
    }
    return NO;
}

- (BOOL)isFavoriteSmileyFromApp:(NSString*)sCode {
    for (int i = 0; i < self.arrFavoritesSmileysApp.count; i++) {
        if ([[[self.arrFavoritesSmileysApp objectAtIndex:i] objectForKey:@"code"] isEqualToString:sCode]) {
            return YES;
        }
    }
    return NO;
}

- (BOOL)isFavoriteSmileyFromForum:(NSString*)sCode {
    for (int i = 0; i < self.arrFavoritesSmileysForum.count; i++) {
        if ([[[self.arrFavoritesSmileysForum objectAtIndex:i] objectForKey:@"code"] isEqualToString:sCode]) {
            return YES;
        }
    }
    return NO;
}

@end
