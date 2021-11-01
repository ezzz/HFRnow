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
#import "UIImage+GIF.h"

#define IMAGE_CACHE_MAX_ELEMENTS 1000
#define IMAGE_CACHE_SMILEYS_DEFAULTS_MAX_ELEMENTS 50
#define SMILEY_CACHE_FAVORITES_DIC @"smiley_favorites_cache"

@implementation SmileyRequest
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

@synthesize arrCurrentSmileyArray, arrCustomSmileys, cacheSmileys, cacheSmileysDefaults, bStopLoadingSmileysSearchToCache, bStopLoadingSmileysCustomToCache, dicCommonSmileys, dicSearchSmileys, bSearchSmileysActivated;

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
        self.arrCustomSmileys = nil;
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
                NSLog(@"index %ld not imported", (long)index);
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
            UIImage *image = [UIImage sd_animatedGIFWithData:imgData];
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
    self.arrCustomSmileys = [arrSmileys mutableCopy];

    // Adding favorites smileys to custom smileys
    [self.dicFavoritesSmileys enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL* stop) {
        NSLog(@"Adding dicFavoritesSmileys :  %@ => %@", key, value);
        [self.arrCustomSmileys addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:value, key, nil] forKeys:[NSArray arrayWithObjects:@"source", @"code", nil]]];
    }];

    
    for (int i = 0; i < self.arrCustomSmileys.count; i++) {
        NSString *filename = [[[self.arrCustomSmileys objectAtIndex:i] objectForKey:@"source"] stringByReplacingOccurrencesOfString:@"http://forum-images.hardware.fr/" withString:@""];
        filename = [filename stringByReplacingOccurrencesOfString:@"https://forum-images.hardware.fr/" withString:@""];

        //NSLog(@"URL custom: %@ ", [NSString stringWithFormat:@"%@", [[self.arrCustomSmileys objectAtIndex:i] objectForKey:@"source"]]);

        NSData* imgData = [NSData dataWithContentsOfURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@", [[[self.arrCustomSmileys objectAtIndex:i] objectForKey:@"source"] stringByAddingPercentEscapesUsingEncoding:NSASCIIStringEncoding]]]];

        if (imgData) {
            UIImage *image = [UIImage sd_animatedGIFWithData:imgData];
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
    self.bStopLoadingSmileysCustomToCache = YES;
    NSLog(@"Finished loading all smileys");
}

- (UIImage*) getImageForIndex:(int)index forCollection:(UICollectionView*)cv andIndexPath:(NSIndexPath*)ip customSmiley:(BOOL)bCustomSmiley
{
    NSString *filename = nil;
    if (bCustomSmiley) {
        filename = [[[self.arrCustomSmileys objectAtIndex:index] objectForKey:@"source"] stringByReplacingOccurrencesOfString:@"http://forum-images.hardware.fr/" withString:@""];
    }
    else {
        filename = [[[self.arrCurrentSmileyArray objectAtIndex:index] objectForKey:@"source"] stringByReplacingOccurrencesOfString:@"http://forum-images.hardware.fr/" withString:@""];
    }
    filename = [filename stringByReplacingOccurrencesOfString:@"https://forum-images.hardware.fr/" withString:@""];
    UIImage* image = nil;
    ImageInCache* iic = [self.cacheSmileys objectForKey:filename];
    if (iic) {
        image = iic.image;
    }

    if (image == nil && ((!bCustomSmiley && self.bStopLoadingSmileysSearchToCache) || (bCustomSmiley && self.bStopLoadingSmileysCustomToCache)))
    {
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
            //NSLog(@"Reloading image at index (%d) : %@", index, filename);
            NSString* source = nil;
            if (bCustomSmiley) {
                source  = [[self.arrCustomSmileys objectAtIndex:index] objectForKey:@"source"];
            }
            else {
                if (index < self.arrCurrentSmileyArray.count) {
                    source  = [[self.arrCurrentSmileyArray objectAtIndex:index] objectForKey:@"source"];
                }
                else {
                    NSLog(@"ERROR in index of arrCustomSmileys. index %ld / %ld", (long)index, (long)self.arrCustomSmileys.count);
                }
            }
            
            if (source) {
                NSData* imgData = [NSData dataWithContentsOfURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@", [source stringByAddingPercentEscapesUsingEncoding:NSASCIIStringEncoding]]]];
                if (imgData) {
                    UIImage* image = [UIImage sd_animatedGIFWithData:imgData];
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
        image = [UIImage sd_animatedGIFWithData:imgData];
        //NSLog(@"%@ size : (%f) %f x %f", filename, image.scale, image.size.width, image.size.height);
        [self.cacheSmileysDefaults setObject:image forKey:filename];
    }
    return image;
}

- (NSString*) getSmileyCodeForIndex:(int)index bCustom:(BOOL)bCustom
{
    if (bCustom) {
        return [[self.arrCustomSmileys objectAtIndex:index] objectForKey:@"code"];
    }
    else {
        return [[self.arrCurrentSmileyArray objectAtIndex:index] objectForKey:@"code"];
    }
}
- (NSString*) getSmileyImgUrlForIndex:(int)index bCustom:(BOOL)bCustom
{
    if (bCustom) {
        return [[self.arrCustomSmileys objectAtIndex:index] objectForKey:@"source"];
    }
    else {
        return [[self.arrCurrentSmileyArray objectAtIndex:index] objectForKey:@"source"];
    }
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
          NSLog(@"Loading dicFavoritesSmileys :  %@ => %@", key, value);
        }];
    }
    else {
        self.dicFavoritesSmileys = [[NSMutableDictionary alloc] init];
    }
}

- (BOOL)AddAndSaveDicFavorites:(NSString*)sCode source:(NSString*)sSource addSmiley:(BOOL)bAdd {
    NSString *directory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    NSString *filename = [[NSString alloc] initWithString:[directory stringByAppendingPathComponent:SMILEY_CACHE_FAVORITES_DIC]];
    
    NSMutableData *data = [[NSMutableData alloc] init];
    NSKeyedArchiver *archiver = [[NSKeyedArchiver alloc] initForWritingWithMutableData:data];// error:&error];
    BOOL bShouldSaveToFile = YES;
    if (bAdd) {
        NSLog(@"Adding dicFavoritesSmileys :  %@ => %@", sCode, sSource);
        [self.dicFavoritesSmileys setObject:sSource forKey:sCode];
        [self.arrCustomSmileys addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:sSource, sCode, nil] forKeys:[NSArray arrayWithObjects:@"source", @"code", nil]]];
    }
    else {
        [self.dicFavoritesSmileys removeObjectForKey:sCode];
        int index = -1;
        for (int i = 0; i < self.arrCustomSmileys.count; i++) {
            if ([[[self.arrCustomSmileys objectAtIndex:i] objectForKey:@"code"] isEqualToString:sCode]) {
                index = i;
                break;
            }
        }
        if (index >= 0) {
            [self.arrCustomSmileys removeObjectAtIndex:index];
        }
        else {
            bShouldSaveToFile = NO;
        }
    }
    if (bShouldSaveToFile) {
        [self.dicFavoritesSmileys enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL* stop) {
          NSLog(@"Saving dicFavoritesSmileys :  %@ => %@", key, value);
        }];
        [archiver encodeObject:self.dicFavoritesSmileys];
        [archiver finishEncoding];
        return [data writeToFile:filename atomically:YES];
    }
    return NO;
}

@end
