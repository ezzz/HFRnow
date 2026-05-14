//
//  ObjCFavoritesLoaderWorker.m
//  HFRplus
//

#import "ObjCFavoritesLoaderWorker.h"

#import "ASIHTTPRequest.h"
#import "Constants.h"
#import "Favorite.h"
#import "Forum.h"
#import "HFRplusAppDelegate.h"
#import "HTMLParser.h"
#import "HTMLNode.h"
#import "RegexKitLite.h"
#import "Topic.h"
#import "k.h"

@interface ObjCFavoritesLoaderWorker ()
@property (nonatomic, strong) NSMutableArray<Favorite *> *arrayCategories;
@property (nonatomic, strong) NSMutableArray<Favorite *> *arrayNewData;
@property (nonatomic, strong) NSMutableArray<Topic *> *arrayTopics;
@property (nonatomic, strong) NSMutableArray<NSString *> *arrayCategoriesVisibleOrder;
@property (nonatomic, strong) NSMutableArray<NSString *> *arrayCategoriesHiddenOrder;
@end

@implementation ObjCFavoritesLoaderWorker

- (instancetype)init {
    self = [super init];
    if (self) {
        NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
        self.arrayCategories = [[NSMutableArray alloc] init];
        self.arrayNewData = [[NSMutableArray alloc] init];
        self.arrayTopics = [[NSMutableArray alloc] init];
        self.arrayCategoriesVisibleOrder = [[defaults arrayForKey:@"arrayCategoriesVisibleOrder"] mutableCopy] ?: [[NSMutableArray alloc] init];
        self.arrayCategoriesHiddenOrder = [[defaults arrayForKey:@"arrayCategoriesHiddenOrder"] mutableCopy] ?: [[NSMutableArray alloc] init];
    }
    return self;
}

- (void)fetchContentWithCompletion:(void (^)(NSArray<Favorite *> *, NSError *))completion {
    self.completion = completion;

    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSInteger vosSujets = [defaults integerForKey:@"vos_sujets"];
    NSString *ownTopic = vosSujets == 1 ? @"3" : @"1";
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@/forum1f.php?owntopic=%@", [k ForumURL], ownTopic]];

    [ASIHTTPRequest setDefaultTimeOutSeconds:kTimeoutMini];
    self.request = [ASIHTTPRequest requestWithURL:url];
    [self.request setDelegate:self];
    [self.request setDidFinishSelector:@selector(fetchContentComplete:)];
    [self.request setDidFailSelector:@selector(fetchContentFailed:)];
    [self.request startAsynchronous];
}

- (void)cancelFetchContent {
    [self.request cancel];
}

- (void)fetchContentComplete:(ASIHTTPRequest *)request {
    @try {
        NSArray<Favorite *> *favorites = [self parseFavoritesFromData:[request responseData]];
        [self finishWithFavorites:favorites error:nil];
    }
    @catch (NSException *exception) {
        NSError *error = [NSError errorWithDomain:@"ObjCFavoritesLoaderWorker"
                                             code:2
                                         userInfo:@{NSLocalizedDescriptionKey: exception.reason ?: @"Erreur favoris"}];
        [self finishWithFavorites:nil error:error];
    }
}

- (void)fetchContentFailed:(ASIHTTPRequest *)request {
    [self finishWithFavorites:nil error:request.error];
}

- (NSArray<Favorite *> *)parseFavoritesFromData:(NSData *)contentData {
    self.arrayCategories = [[NSMutableArray alloc] init];
    self.arrayNewData = [[NSMutableArray alloc] init];
    self.arrayTopics = [[NSMutableArray alloc] init];

    HTMLParser *parser = [[HTMLParser alloc] initWithData:contentData error:NULL];
    HTMLNode *bodyNode = [parser body];

    if (![bodyNode getAttributeNamed:@"id"]) {
        NSString *message = @"Authentification requise";
        if ([[[bodyNode firstChild] tagName] isEqualToString:@"p"]) {
            message = [[[bodyNode firstChild] contents] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        } else {
            message = [[[bodyNode findChildWithAttribute:@"class" matchingName:@"hop" allowPartial:NO] contents] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]] ?: message;
        }
        @throw [NSException exceptionWithName:@"FavoritesLoadError" reason:message userInfo:nil];
    }

    HTMLNode *mpNode = [bodyNode findChildOfClass:@"none"];
    NSArray *temporaryMPArray = [mpNode findChildTags:@"td"];
    if (temporaryMPArray.count == 3) {
        NSString *regExMP = @"[^.0-9]+([0-9]{1,})[^.0-9]+";
        NSString *myMPNumber = [[[temporaryMPArray objectAtIndex:1] allContents] stringByReplacingOccurrencesOfRegex:regExMP withString:@"$1"];
        [[HFRplusAppDelegate sharedAppDelegate] updateMPBadgeWithString:myMPNumber];
    }

    HTMLNode *hashCheck = [bodyNode findChildWithAttribute:@"name" matchingName:@"hash_check" allowPartial:NO];
    [[HFRplusAppDelegate sharedAppDelegate] setHash_check:[hashCheck getAttributeNamed:@"value"]];

    HTMLNode *tableNode = [bodyNode findChildWithAttribute:@"class" matchingName:@"main" allowPartial:NO];
    NSArray *temporaryFavoriteArray = [tableNode findChildTags:@"tr"];

    BOOL first = YES;
    BOOL catOrderIsEmpty = self.arrayCategoriesVisibleOrder.count + self.arrayCategoriesHiddenOrder.count == 0;
    int order = 0;
    Favorite *currentFavorite = nil;
    NSMutableArray<Favorite *> *visibleCategories = [[NSMutableArray alloc] init];
    NSMutableArray<Favorite *> *hiddenCategories = [[NSMutableArray alloc] init];
    NSMutableArray<Topic *> *topics = [[NSMutableArray alloc] init];

    for (HTMLNode *trNode in temporaryFavoriteArray) {
        if ([[trNode className] rangeOfString:@"fondForum1fCat"].location != NSNotFound) {
            if (!first) {
                [self appendFavorite:currentFavorite visibleCategories:visibleCategories hiddenCategories:hiddenCategories topics:topics];
            }

            currentFavorite = [[Favorite alloc] init];
            [currentFavorite parseNode:trNode];

            if (catOrderIsEmpty) {
                currentFavorite.order = [NSNumber numberWithInt:order];
                order++;
                [self.arrayCategoriesVisibleOrder addObject:currentFavorite.forum.aID];
            } else {
                NSUInteger visibleOrder = [self.arrayCategoriesVisibleOrder indexOfObject:currentFavorite.forum.aID];
                if (visibleOrder == NSNotFound) {
                    NSUInteger hiddenOrder = [self.arrayCategoriesHiddenOrder indexOfObject:currentFavorite.forum.aID];
                    if (hiddenOrder == NSNotFound) {
                        currentFavorite.order = [NSNumber numberWithInteger:self.arrayCategoriesVisibleOrder.count];
                        [self.arrayCategoriesVisibleOrder addObject:currentFavorite.forum.aID];
                    } else {
                        currentFavorite.order = [NSNumber numberWithUnsignedInteger:hiddenOrder];
                    }
                } else {
                    currentFavorite.order = [NSNumber numberWithUnsignedInteger:visibleOrder];
                    [self.arrayCategoriesHiddenOrder removeObject:currentFavorite.forum.aID];
                }
            }
            first = NO;
        } else if ([[trNode className] rangeOfString:@"ligne_booleen"].location != NSNotFound) {
            [currentFavorite addTopicWithNode:trNode];
        }
    }

    if (!first) {
        [self appendFavorite:currentFavorite visibleCategories:visibleCategories hiddenCategories:hiddenCategories topics:topics];
    }

    [[NSUserDefaults standardUserDefaults] setObject:self.arrayCategoriesVisibleOrder forKey:@"arrayCategoriesVisibleOrder"];
    [[NSUserDefaults standardUserDefaults] setObject:self.arrayCategoriesHiddenOrder forKey:@"arrayCategoriesHiddenOrder"];
    [[NSUserDefaults standardUserDefaults] synchronize];

    NSSortDescriptor *sortDescriptor = [[NSSortDescriptor alloc] initWithKey:@"order" ascending:YES selector:@selector(compare:)];
    self.arrayCategories = [NSMutableArray arrayWithArray:[visibleCategories sortedArrayUsingDescriptors:@[sortDescriptor]]];

    NSSortDescriptor *sortDescriptorDate = [[NSSortDescriptor alloc] initWithKey:@"dDateOfLastPost" ascending:NO selector:@selector(compare:)];
    self.arrayTopics = [NSMutableArray arrayWithArray:[topics sortedArrayUsingDescriptors:@[sortDescriptorDate]]];

    return [self.arrayCategories copy];
}

- (void)appendFavorite:(Favorite *)favorite
     visibleCategories:(NSMutableArray<Favorite *> *)visibleCategories
      hiddenCategories:(NSMutableArray<Favorite *> *)hiddenCategories
                topics:(NSMutableArray<Topic *> *)topics {
    if ([self.arrayCategoriesVisibleOrder containsObject:favorite.forum.aID]) {
        if (favorite.topics.count > 0) {
            [self.arrayNewData addObject:favorite];
            for (Topic *topic in favorite.topics) {
                [topics addObject:topic];
            }
        }
        [visibleCategories addObject:favorite];
    } else {
        [hiddenCategories addObject:favorite];
    }
}

- (void)finishWithFavorites:(NSArray<Favorite *> *)favorites error:(NSError *)error {
    void (^completion)(NSArray<Favorite *> *, NSError *) = self.completion;
    self.completion = nil;
    if (!completion) { return; }

    dispatch_async(dispatch_get_main_queue(), ^{
        completion(favorites, error);
    });
}

@end
