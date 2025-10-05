//
//  FilterPostsQuotes.m
//  SuperHFRplus
//
//  Created by ezzz on 05/04/2020.
//

#import "FilterPostsQuotes.h"
#import "ASIHTTPRequest+Tools.h"
#import "ASIFormDataRequest.h"
#import "HTMLParser.h"
#import "RegexKitLite.h"
#import "ASIHTTPRequest.h"
#import "Constants.h"
#import "ParseMessagesOperation.h"
#import "FavoritesTableViewController.h"
#import "MessagesTableViewController.h"
#import "HFRAlertView.h"
#import "Favorite.h"

@implementation FilterPostsQuotes

@synthesize topic, request, arrData, iLastPageLoaded, bIsFinished, progressView, alertProgress, favoriteVC, messagesTableVC, bShowPostsRequired, stopRequired;

//static FilterPostsQuotes *_shared = nil;    // static instance variable

// --------------------------------------------------------------------------------
#pragma mark Init methods
// --------------------------------------------------------------------------------

/*
+ (FilterPostsQuotes *)shared {
    if (_shared == nil) {
        _shared = [[super allocWithZone:NULL] init];
    }
    return _shared;
}*/

- (id)init {
    if ( (self = [super init]) ) {
        // your custom initialization
        self.bProcessingOnlyQuotes = NO;
        _pageCache = [[NSCache alloc] init];
        _pageCache.name = @"TopicsFetcher.PageCache";
        self.dDateOfLastFetchContent = nil;
    }
    return self;
}

#pragma mark - Main method

- (void)checkPostsAndQuotesForTopic:(Topic *)topic andVC:(FavoritesTableViewController*) vc{
    self.favoriteVC = vc;
    self.messagesTableVC = nil;
    self.bOnlyQuotes = NO;

    [self addProgressBar:vc];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self fetchContentForTopic:topic];
    });
}

- (void)checkNextPostsAndQuotesWithVC:(MessagesTableViewController*) vc {
    self.bOnlyQuotes = NO;
    self.messagesTableVC = vc;

    [self addProgressBar:vc];
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self fetchContentForTopic:self.topic startPage:self.iLastPageLoaded + 1];
    });
}

- (void)checkQuotesForAllTopics:(NSMutableArray*)arrFavoris
                          andVC:(FavoritesTableViewController*) vc
                     autoCheck:(BOOL)bAutoCheck {
    self.bOnlyQuotes = YES;
    self.favoriteVC = vc;
    self.messagesTableVC = nil;
    
    // If already processing, stop
    BOOL bAskToStop = NO;
    if (self.bProcessingOnlyQuotes) {
        bAskToStop = YES;
    } else {
        self.bProcessingOnlyQuotes = YES;
    }
    
    // Timeout global
    NSTimeInterval globalTimeout = 20.0;
    NSDate *startTime = [NSDate date];
    
    NSLog(@"checkQuotesForAllTopics nb cat %ld", (long)arrFavoris.count);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        // --- PRIORISATION ---
        // On prépare deux listes pour conserver l'ordre d'origine dans chaque groupe
        NSMutableArray<NSDictionary *> *flatListSuper = [NSMutableArray array];
        NSMutableArray<NSDictionary *> *flatListRegular = [NSMutableArray array];
        
        for (NSInteger section = 0; section < arrFavoris.count; section++) {
            Favorite *favori = arrFavoris[section];
            for (NSInteger row = 0; row < favori.topics.count; row++) {
                Topic *topic = favori.topics[row];
                NSDictionary *entry = @{
                    @"topic": topic,
                    @"section": @(section),
                    @"row": @(row)
                };
                
                // Test si superFavori
                if ([self.favoriteVC.idPostSuperFavorites containsObject:[NSNumber numberWithInt:topic.postID]] ) {
                    if (self.dDateOfLastFetchContent == nil) { // Si last check jamais fait
                        [flatListSuper addObject:entry];
                    }
                    else {
                        NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:self.dDateOfLastFetchContent];
                        if (elapsed >= 120.0) { // On ne check pas les super favoris plus souvent que 120s
                            [flatListSuper addObject:entry];
                        }
                    }
                } else { // Si NON super favori
                    if (self.dDateOfLastFetchContent == nil) { // Si last check jamais fait
                        [flatListRegular addObject:entry];
                    }
                    else {  // On ne check pas les NON super favoris plus souvent que 10mi
                        NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:self.dDateOfLastFetchContent];
                        if (elapsed >= 3600.0) {
                            [flatListRegular addObject:entry];
                        }
                    }
                }
            }
        }
        
        // Concaténation : les super favoris en premier
        NSMutableArray<NSDictionary *> *flatList = [NSMutableArray arrayWithArray:flatListSuper];
        [flatList addObjectsFromArray:flatListRegular];
        // --- FIN PRIORISATION ---
        
        NSLog(@"flatList nb topics %ld (super:%ld / regular:%ld)",
              (long)flatList.count, (long)flatListSuper.count, (long)flatListRegular.count);

        NSInteger batchSize = 1;
        NSInteger count = flatList.count;
        
        for (NSInteger i = 0; i < count; i += batchSize) {
            // Timeout global
            if ([[NSDate date] timeIntervalSinceDate:startTime] > globalTimeout || bAskToStop) {
                NSLog(@"⏱ Timeout global atteint ou demande d'arret, on arrête");
                break;
            }
            
            dispatch_group_t group = dispatch_group_create();
            NSRange range = NSMakeRange(i, MIN(batchSize, count - i));
            NSArray *batch = [flatList subarrayWithRange:range];
            
            for (NSDictionary *item in batch) {
                Topic *topic = item[@"topic"];
                NSNumber *sectionNum = item[@"section"];
                NSNumber *rowNum = item[@"row"];
                
                NSIndexPath *indexPath = [NSIndexPath indexPathForRow:rowNum.integerValue
                                                            inSection:sectionNum.integerValue];
                
                NSDate* startFetch = [NSDate date];
                dispatch_group_enter(group);
                [self fetchContentForTopic:topic completion:^(Topic *finishedTopic) {
                    // Le topic a mis à jour finishedTopic.hasBeenQuoted

                    NSTimeInterval timeFetch = [[NSDate date] timeIntervalSinceDate:startFetch];
                    NSLog(@"Durée fetch total %.1f pour %@", timeFetch, topic._aTitle);
                    dispatch_async(dispatch_get_main_queue(), ^{
                        NSLog(@"Reload cell for topic %@ section %@ row %@", topic._aTitle, sectionNum, rowNum);
                        [self.favoriteVC.favoritesTableView reloadRowsAtIndexPaths:@[indexPath]
                                                         withRowAnimation:UITableViewRowAnimationNone];
                    });
                    dispatch_group_leave(group);
                }];
            }
            
            // Attente de fin du batch (avec timeout restant)
            NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:startTime];
            NSTimeInterval remaining = MAX(0, globalTimeout - elapsed);
            long result = dispatch_group_wait(group,
                         dispatch_time(DISPATCH_TIME_NOW, (int64_t)(remaining * NSEC_PER_SEC)));
            
            if (result != 0) {
                NSLog(@"⚠️ Timeout pendant un batch, arrêt");
                break;
            }
        }
        self.dDateOfLastFetchContent = [NSDate date];
        NSLog(@"✅ Tous les topics traités (ou interrompus)");
        self.bProcessingOnlyQuotes = NO;
        /*dispatch_async(dispatch_get_main_queue(), ^{
            self.favoriteVC.navigationItem.rightBarButtonItems[1].image = [UIImage systemImageNamed:@"text.bubble"];
        });`*/
    });
}


#pragma mark - Work methods



- (void)fetchContentForTopic:(Topic*)topic {
    [self fetchContentForTopic:topic startPage:0];
}

- (void)fetchContentForTopic:(Topic*)topic completion:(void (^)(Topic *topic))completion {
    
    NSDate* startFetch = [NSDate date];
    [self fetchContentForTopic:topic startPage:0];
    NSTimeInterval timeFetch = [[NSDate date] timeIntervalSinceDate:startFetch];
    NSLog(@"Durée fetch2 %.1f pour %@", timeFetch, topic._aTitle);

    if (completion) {
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(topic);
        });
    }
}

- (NSMutableDictionary *)cacheForTopic:(Topic *)topic {
    NSNumber *cacheKey = @(topic.postID);
    NSMutableDictionary *topicCache = [self.pageCache objectForKey:cacheKey];
    if (!topicCache) {
        topicCache = [NSMutableDictionary dictionary];
        topicCache[@"pages"] = [NSMutableDictionary dictionary];
        [self.pageCache setObject:topicCache forKey:cacheKey];
    }
    return topicCache;
}

- (void)invalidateCacheForTopic:(Topic *)topic {
    NSMutableDictionary *topicCache = [self cacheForTopic:topic];
    NSMutableDictionary *pages = topicCache[@"pages"];
    NSArray<NSNumber *> *keys = [pages allKeys];

    for (NSNumber *pageNum in keys) {
        if (pageNum.intValue < topic.curTopicPage) {
            [pages removeObjectForKey:pageNum];
            NSLog(@"[CACHE] Invalidation page %@ pour topic %d", pageNum, topic.postID);
        }
    }
}

- (void)fetchContentForTopic:(Topic*)topic startPage:(int)iStartPage {
    self.topic = topic;
    [ASIHTTPRequest setDefaultTimeOutSeconds:kTimeoutMini];
    self.arrData = [[NSMutableArray alloc] init];
    self.bShowPostsRequired = NO;
    self.stopRequired = NO;
    self.bIsFinished = NO;
    
    // 🔄 Invalidation automatique avant de commencer
     [self invalidateCacheForTopic:topic];
    
    int iPageToLoad = topic.curTopicPage;
    if (iStartPage > 0) {
        iPageToLoad = iStartPage;
    }
    self.iStartPage = iPageToLoad;
    NSString* sStartAfterPostId = nil;
    if (iStartPage == 0) {
        NSRange foundRange = [topic.aURL rangeOfString:@"#t"];
        if (foundRange.location != NSNotFound) {
            NSRange rangeRes = NSMakeRange(foundRange.location + 1, topic.aURL.length - foundRange.location - 1);
            sStartAfterPostId = [topic.aURL substringWithRange:rangeRes];
        }
    }
    
    NSNumber *cacheKey = @(topic.postID);
    NSMutableDictionary *topicCache = [self cacheForTopic:topic];
    NSMutableDictionary<NSNumber *, NSDictionary *> *pagesCache = topicCache[@"pages"];
    NSDate *lastFetchDate = topicCache[@"lastFetchDate"];
        
    int iNbPagesLoaded = 0;
    while (iPageToLoad <= topic.maxTopicPage) {
        
        BOOL isLastPage = (iPageToLoad == topic.maxTopicPage);
        NSNumber *pageNum = @(iPageToLoad);

        NSDictionary *cachedResult = pagesCache[pageNum];
        
        // --- Vérification cache pour pages intermédiaires ---
        if (!isLastPage && cachedResult) {
            NSLog(@"[CACHE] Using cached page %d for topic %d", iPageToLoad, topic.postID);
            if ([cachedResult[@"isQuoted"] boolValue]) {
                topic.isFavoriteQuoted = YES;
                self.bIsFinished = YES;
                break;
            }
            iPageToLoad++;
            continue;
        }
        
        // --- Vérification cache pour dernière page ---
        // ✅ Dernière page → check date
        if (isLastPage && cachedResult && lastFetchDate && topic.dDateOfLastPost &&
            [topic.dDateOfLastPost compare:lastFetchDate] == NSOrderedAscending) {
            topic.isFavoriteQuoted = [cachedResult[@"isQuoted"] boolValue];
            NSLog(@"[CACHE] Last page reused for topic %d (no new posts)", topic.postID);
            self.bIsFinished = YES;
            break;
        }
        
        NSLog(@"Loading Topic page %d - %@", iPageToLoad, topic._aTitle);
        NSDate* start2 = [NSDate date];
        NSDate* startFetch = [NSDate date];

        if (self.bOnlyQuotes && !self.bProcessingOnlyQuotes) {
            NSLog(@"Stop processing !");
            return;
        }
        NSString* sURL = [NSString stringWithFormat:@"https://forum.hardware.fr%@", [topic getURLforPage:iPageToLoad]];
        ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:sURL]];
        [request setShouldRedirect:YES];
        [request setDelegate:self];
        [request setUseCookiePersistence:NO];
        [request setRequestCookies:[[NSMutableArray alloc]init]];
        [request startSynchronous];
        if (request) {
            if ([request error]) {
                NSLog(@"error: %@", [[request error] localizedDescription]);
                return;
            }
            NSData* data = [request safeResponseData];
            
            NSTimeInterval timeFetch = [[NSDate date] timeIntervalSinceDate:startFetch];
            NSLog(@"Durée request %.1f pour %@", timeFetch, topic._aTitle);
            
            NSDate* startParse = [NSDate date];

            if (data) {
                ParseMessagesOperation *parser = [[ParseMessagesOperation alloc] initWithData:data index:0 reverse:NO delegate:nil];
                NSError * error = nil;
                parser.bOnlyQuotes = self.bOnlyQuotes;
                HTMLParser *myParser = [[HTMLParser alloc] initWithData:data error:&error];
                [parser parseData:myParser filterPostsQuotes:YES startAfterThisPostId:sStartAfterPostId topicUrl:topic.aURL topicPage:iPageToLoad];
                sStartAfterPostId = nil; // On filter on first page of url, not on the following
                self.arrData = [self.arrData arrayByAddingObjectsFromArray:parser.workingArray];
                
                NSTimeInterval timeParse = [[NSDate date] timeIntervalSinceDate:startParse];
                NSLog(@"Durée parse %.1f pour %@", timeParse, topic._aTitle);

                BOOL pageHasQuote = NO;
                if (self.bOnlyQuotes && parser.bFoundQuote) {
                    pageHasQuote = YES;
                    NSLog(@"FOUND !!!");
                    self.topic.isFavoriteQuoted = YES;
                    NSLog(@"Load cell %@ isQuoted %d", self.topic._aTitle, self.topic.isFavoriteQuoted);
                    self.bIsFinished = YES;
                    break;
                }
                
                // 📝 Mise à jour cache
                pagesCache[pageNum] = @{ @"isQuoted": @(pageHasQuote) };
                topicCache[@"lastFetchDate"] = [NSDate date];
            }
        }
        if (self.arrData.count > 0) {
            dispatch_async(dispatch_get_main_queue(), ^{
                NSArray* arrActions = [self.alertProgress actions];
                [arrActions[0] setEnabled:YES];
            });
        }
        float fProgress = ((float)iNbPagesLoaded+1)/(topic.maxTopicPage - self.iStartPage);
        NSString* sMessage = @"Aucun post trouvé";
        if (self.arrData.count == 1) {
            sMessage = @"1 post trouvé";
        }
        else if (self.arrData.count > 1) {
            sMessage = [NSString stringWithFormat:@"%ld posts trouvés", (long)self.arrData.count];
        }
        sMessage = [NSString stringWithFormat:@"%@\n%ld/%ld", sMessage, (unsigned long)iPageToLoad, (unsigned long)topic.maxTopicPage];
        [self updateProgressBarWithPercent:fProgress andMessage:sMessage];
        
        if (iPageToLoad == topic.maxTopicPage) {
            self.bIsFinished = YES;
            break;
        }
        else if (self.bOnlyQuotes && iNbPagesLoaded == 1) { // en mode CheckAllQuotes, on ne charge que 2 pages
            self.bIsFinished = YES;
            break;
        }
        else if (self.arrData.count >= 40 || self.bShowPostsRequired || self.stopRequired) {
            break;
        }
        else {
            iPageToLoad++;
            iNbPagesLoaded++;
        }
        NSTimeInterval time2 = [[NSDate date] timeIntervalSinceDate:start2];
        NSLog(@"Durée parse %.1f pour %@", time2, topic._aTitle);
    }
    self.iLastPageLoaded = iPageToLoad;
    if (!self.bOnlyQuotes && !self.stopRequired && (self.arrData.count >= 40 || self.bShowPostsRequired || (self.arrData.count >= 1 && bIsFinished))) {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressView.progress = 1.0;
        });
        [NSThread sleepForTimeInterval:1];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.alertProgress dismissViewControllerAnimated:YES completion:^{
                if (self.messagesTableVC) {
                    [self displayNextPosts];
                }
                else {
                    [self displayPosts:topic];
                }
            }];
        });
    } else {
        dispatch_async(dispatch_get_main_queue(), ^{
            self.progressView.progress = 1.0;
            [self.alertProgress setTitle:@"Résultat"];
            NSArray* arrActions = [self.alertProgress actions];
            [arrActions[1] setTitle:@"Fermer"];
        });
        //[NSThread sleepForTimeInterval:2];
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.alertProgress dismissViewControllerAnimated:YES completion:nil];
        });
    }
}

// --------------------------------------------------------------------------------
#pragma mark -
#pragma mark HMI methods
// --------------------------------------------------------------------------------

- (void)addProgressBar:(UIViewController*)vc {
    self.alertProgress = [UIAlertController alertControllerWithTitle:@"Chargement..."
                                                             message:nil   // <== pas de message => moins d'espace
                                                      preferredStyle:UIAlertControllerStyleAlert];

    // Boutons
    UIAlertAction* actionAfficher = [UIAlertAction actionWithTitle:@"Afficher"
                                                             style:UIAlertActionStyleDefault
                                                           handler:^(UIAlertAction * _Nonnull action) {
        self.bShowPostsRequired = YES;
    }];
    [actionAfficher setEnabled:NO];
    [self.alertProgress addAction:actionAfficher];

    [self.alertProgress addAction:[UIAlertAction actionWithTitle:@"Annuler"
                                                           style:UIAlertActionStyleCancel
                                                         handler:^(UIAlertAction * _Nonnull action) {
        self.stopRequired = YES;
    }]];

    // VC contenant la progress bar
    UIViewController *contentVC = [[UIViewController alloc] init];
    UIProgressView *progress = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    progress.translatesAutoresizingMaskIntoConstraints = NO;
    [contentVC.view addSubview:progress];

    [NSLayoutConstraint activateConstraints:@[
        [progress.leadingAnchor constraintEqualToAnchor:contentVC.view.leadingAnchor constant:8],
        [progress.trailingAnchor constraintEqualToAnchor:contentVC.view.trailingAnchor constant:-8],
        [progress.topAnchor constraintEqualToAnchor:contentVC.view.topAnchor constant:4],
        [progress.bottomAnchor constraintEqualToAnchor:contentVC.view.bottomAnchor constant:-4]
    ]];

    self.progressView = progress;

    // Injection
    [self.alertProgress setValue:contentVC forKey:@"contentViewController"];

    [vc presentViewController:self.alertProgress animated:YES completion:nil];
}



-(void) updateProgressBarWithPercent:(float)fPercent andMessage:(NSString*)sMessage {
    dispatch_async(dispatch_get_main_queue(), ^{
        //[self.alertProgress setMessage:[NSString stringWithFormat:@"%@", sMessage]];
        self.progressView.progress = fPercent;
        [self.alertProgress setMessage:sMessage];
    });
}
-(void) closeProgressView {
    dispatch_async(dispatch_get_main_queue(), ^{
    });
}
-(void) displayPosts:(Topic*)topic {
    MessagesTableViewController *aView = [[MessagesTableViewController alloc] initWithNibName:@"MessagesTableViewController" bundle:nil andUrl:topic.aURL displaySeparator:YES];
    self.favoriteVC.messagesTableViewController = aView;

    //setup the URL
    self.favoriteVC.messagesTableViewController.filterPostsQuotes = self;
    self.favoriteVC.messagesTableViewController.topic = topic;
    self.favoriteVC.messagesTableViewController.topicName = topic.aTitle;

    //NSLog(@"push message liste");
    [self.favoriteVC pushTopic];
}

-(void) displayNextPosts {
    self.messagesTableVC.pageNumberFilterStart = self.iStartPage;
    self.messagesTableVC.pageNumberFilterEnd = self.iLastPageLoaded;
    [self.messagesTableVC manageLoadedItems:self.arrData];
    self.messagesTableVC.pageNumberFilterStart = self.iStartPage;
    self.messagesTableVC.pageNumberFilterEnd = self.iLastPageLoaded;
    [self.messagesTableVC setupScrollAndPage];
}

@end
