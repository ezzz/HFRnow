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


/*
- (void)checkQuotesForAllTopics:(NSMutableArray *)arrTopics andVC:(FavoritesTableViewController*) vc {
    
    NSLog(@"checkQuotesForAllTopics nb %ld", arrTopics.count);
    
    self.bOnlyQuotes = YES;
    self.favoriteVC = vc;
    self.messagesTableVC = nil;
    
    // Timeout global en secondes
    NSTimeInterval globalTimeout = 20.0;
    NSDate *startTime = [NSDate date];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        NSInteger batchSize = 3;
        NSInteger count = arrTopics.count;
        
        for (NSInteger i = 0; i < count; i += batchSize) {
            // Vérifier timeout global
            if ([[NSDate date] timeIntervalSinceDate:startTime] > globalTimeout) {
                NSLog(@"⏱ Timeout global atteint, on arrête le traitement");
                break;
            }
            
            // Préparer un groupe pour ce batch
            dispatch_group_t group = dispatch_group_create();
            
            // Prendre jusqu’à 3 topics
            NSRange range = NSMakeRange(i, MIN(batchSize, count - i));
            NSArray *batch = [arrTopics subarrayWithRange:range];
            
            for (Topic *topic in batch) {
                dispatch_group_enter(group);
                
                dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                    
                    // Ton appel asynchrone
                    [self fetchContentForTopic:topic completion:^(Topic *finishedTopic) {
                        NSInteger row = [self.favoriteVC.arrayData indexOfObject:finishedTopic];
                        if (row != NSNotFound) {
                            NSIndexPath *indexPath = [NSIndexPath indexPathForRow:row inSection:0];
                            [self.favoriteVC.favoritesTableView reloadRowsAtIndexPaths:@[indexPath]
                                                             withRowAnimation:UITableViewRowAnimationNone];
                        }
                        dispatch_group_leave(group);
                    }];
                });
            }
            
            // Attendre la fin du batch (ou timeout restant)
            NSTimeInterval elapsed = [[NSDate date] timeIntervalSinceDate:startTime];
            NSTimeInterval remaining = MAX(0, globalTimeout - elapsed);
            
            long result = dispatch_group_wait(group, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(remaining * NSEC_PER_SEC)));
            
            if (result != 0) {
                NSLog(@"⚠️ Timeout atteint pendant un batch, arrêt");
                break;
            }
        }
        
        NSLog(@"✅ Traitement des topics terminé (ou interrompu)");
    });
}*/

- (void)checkQuotesForAllTopics:(NSMutableArray*)arrFavoris
                          andVC:(FavoritesTableViewController*) vc {
    self.bOnlyQuotes = YES;
    self.favoriteVC = vc;
    self.messagesTableVC = nil;
    
    // If already processing, stop
    BOOL bAskToStop = NO;
    if (self.bProcessingOnlyQuotes) {
        bAskToStop = YES;
    }
    else {
        self.bProcessingOnlyQuotes = YES;
    }
    
    // Timeout global
    NSTimeInterval globalTimeout = 120.0;
    NSDate *startTime = [NSDate date];
    
    NSLog(@"checkQuotesForAllTopics nb cat %ld", arrFavoris.count);

    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        
        // Construire une liste plate (favori + topic) pour simplifier les batches
        NSMutableArray<NSDictionary *> *flatList = [NSMutableArray array];
        
        for (NSInteger section = 0; section < arrFavoris.count; section++) {
            Favorite *favori = arrFavoris[section];
            for (NSInteger row = 0; row < favori.topics.count; row++) {
                Topic *topic = favori.topics[row];
                [flatList addObject:@{
                    @"topic": topic,
                    @"section": @(section),
                    @"row": @(row)
                }];
                NSLog(@"Adding topic %@ section %ld row %ld", topic._aTitle, section, row);
            }
        }
        
        NSLog(@"flatList nb topics %ld", flatList.count);

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
                
                dispatch_group_enter(group);
                [self fetchContentForTopic:topic completion:^(Topic *finishedTopic) {
                    // Le topic a mis à jour finishedTopic.hasBeenQuoted
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
        
        NSLog(@"✅ Tous les topics traités (ou interrompus)");
        self.bProcessingOnlyQuotes = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            self.favoriteVC.navigationItem.rightBarButtonItems[1].image = [UIImage systemImageNamed:@"text.bubble"];
        });
    });
}


#pragma mark - Work methods

- (void)fetchContentForTopic:(Topic*)topic {
    [self fetchContentForTopic:topic startPage:0];
}

- (void)fetchContentForTopic:(Topic*)topic completion:(void (^)(Topic *topic))completion {
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [self fetchContentForTopic:topic startPage:0];
        
        // Supposons que ton parsing ait mis à jour topic.hasBeenQuoted
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion(topic);
            });
        }
    });
}

- (void)fetchContentForTopic:(Topic*)topic startPage:(int)iStartPage {
    self.topic = topic;
    [ASIHTTPRequest setDefaultTimeOutSeconds:kTimeoutMaxi];
    self.arrData = [[NSMutableArray alloc] init];
    self.bShowPostsRequired = NO;
    self.stopRequired = NO;
    self.bIsFinished = NO;
    
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
    
    int iNbPagesLoaded = 0;
    while (iPageToLoad <= topic.maxTopicPage) {
        NSLog(@"Loading Topic page %d - %@", iPageToLoad, topic._aTitle);
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
            if (data) {
                ParseMessagesOperation *parser = [[ParseMessagesOperation alloc] initWithData:data index:0 reverse:NO delegate:nil];
                NSError * error = nil;
                parser.bOnlyQuotes = self.bOnlyQuotes;
                HTMLParser *myParser = [[HTMLParser alloc] initWithData:data error:&error];
                [parser parseData:myParser filterPostsQuotes:YES startAfterThisPostId:sStartAfterPostId topicUrl:topic.aURL topicPage:iPageToLoad];
                sStartAfterPostId = nil; // On filter on first page of url, not on the following
                self.arrData = [self.arrData arrayByAddingObjectsFromArray:parser.workingArray];
                if (self.bOnlyQuotes && parser.bFoundQuote) {
                    NSLog(@"FOUND !!!");
                    self.topic.isFavoriteQuoted = YES;
                    NSLog(@"Load cell %@ isQuoted %d", self.topic._aTitle, self.topic.isFavoriteQuoted);
                    self.bIsFinished = YES;
                    break;
                }
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
        [NSThread sleepForTimeInterval:2];
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
