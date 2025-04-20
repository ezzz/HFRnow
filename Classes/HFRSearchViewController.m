//
//  HFRSearchViewController.m
//  HFRplus
//
//  Created by FLK on 04/11/10.
//

#import "HFRplusAppDelegate.h"

#import "HFRSearchViewController.h"
#import "ASIFormDataRequest.h"
#import "HTMLParser.h"
#import "RegexKitLite.h"
#import "TopicSearchCellView.h"
#import "MessagesTableViewController.h"
#import "RangeOfCharacters.h"
#import "HFRplusAppDelegate.h"
#import "ASIHTTPRequest+Tools.h"

#define TIME_OUT_INTERVAL_SEARCH 15

@implementation HFRSearchViewController
@synthesize stories;
@synthesize request;

@synthesize disableViewOverlay, loadingView;
@synthesize status, statusMessage, maintenanceView, messagesTableViewController, tmpCell, pressedIndexPath, topicActionSheet;

@synthesize theSearchBar;

#pragma mark -
#pragma mark Data lifecycle

- (void)createPostString
{
    NSString *searchInput = [self.theSearchBar.text lowercaseString];
    NSArray *bannedWords = [NSArray arrayWithObjects:@"jailbreak", @"cydia", @"pengu", @"apple jb", nil];
    
    for (NSString *word in bannedWords) {
        if ([searchInput rangeOfString:word].location == NSNotFound) {
            //On est bon.
        } else {
            //On est pas bon :o
            searchInput = @"SSBEb24ndCBXYW50IHRvIExpdmUgb24gVGhpcyBQbGFuZXQgQW55bW9yZQ==";
            break;
        }
    }
    
    // Paramètres encodés façon x-www-form-urlencoded
    NSString *postString = [NSString stringWithFormat:
                            @"hash_check=%@&cat=%@&search=%@&resSearch=%@&orderSearch=%@&titre=%@&searchtype=%@&pseud=%@",
                            //@"hash_check=%@&cat=%@&resSearch=%@&orderSearch=%@&titre=%@&searchtype=@%&pseud=%@&rechercherdans=%@",
                            [[HFRplusAppDelegate sharedAppDelegate] hash_check],
                            @"13", // (cat) 13= Discussions
                            [searchInput stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]],
                            @"20", //(resSearch)
                            @"0",//@(sortBy) //0-selon la date des messages trouvés</option>
                            @"1",
                            @"1",
                            @""//,
                            //@"3" // 3-les titres de sujets et le contenu des messages
                        ];

    NSLog(@"POST postString: %@", postString);
    self.dInputPostData = [postString dataUsingEncoding:NSUTF8StringEncoding];
}

- (void)fetchContent
{    NSLog(@"fetchContent");

	[self.stories removeAllObjects];
	
	[self.maintenanceView setHidden:YES];
    [self.topicsTableView setHidden:YES];
	[self.loadingView setHidden:NO];
    
    [self createPostString];
    
    // 1. URL cible
    NSURL *url = [NSURL URLWithString:@"https://forum.hardware.fr/search.php?config=hardwarefr.inc"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    
    // 3. Headers
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    //[request setValue:@"Mozilla/5.0" forHTTPHeaderField:@"User-Agent"];
    [request setHTTPBody:self.dInputPostData];
    //NSString *postLength = [NSString stringWithFormat:@"%ld",[postData length]];
    //[request setValue:postLength forHTTPHeaderField:@"Content-Length"];
    [request setTimeoutInterval:TIME_OUT_INTERVAL_SEARCH];
    
    // 4. Config de session (inclut gestion SSL si nécessaire)
    // Session & tâche
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyAlways;
    config.HTTPCookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    // 5. Envoi async
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"❌ Erreur réseau : %@", error);
        } else {
            //NSLog(@"✅ Statut HTTP : %ld", (long)[(NSHTTPURLResponse *)response statusCode]);
            //NSLog(@"📦 Taille de la réponse : %lu", (unsigned long)data.length);

            //NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            //NSLog(@"🔍 HTML reçu (début) : %@", [html substringToIndex:MIN(html.length, 2000)]);
            
            /*
            NSUInteger length = html.length;
            NSUInteger blockSize = 1000;
            for (NSUInteger i = 0; i < length; i += blockSize) {
                NSUInteger thisBlockSize = MIN(blockSize, length - i);
                NSString *block = [html substringWithRange:NSMakeRange(i, thisBlockSize)];
                NSLog(@"🧩 Bloc %lu : %@", (unsigned long)(i / blockSize + 1), block);
            }*/
            
            NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSString *redirectURL = [self extractRedirectURLFromHTML:html];
            if (redirectURL) {
                NSLog(@"🔁 Redirection trouvée vers : %@", redirectURL);
                //[self followRedirectToURL2:redirectURL];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self followRedirectToURL:redirectURL];
                });
            } else {
                NSLog(@"📄 Pas de redirection détectée.");
            }
        }
        /*HTMLParser * myParser = [[HTMLParser alloc] initWithData:data error:NULL];
        HTMLNode * bodyNode = [myParser body];
        NSLog(@"rawContentsOfNode %@", rawContentsOfNode([bodyNode _node], [myParser _doc]));*/
    }];

    [task resume];
}


- (void)followRedirectToURL:(NSString *)urlString {
    if ([urlString hasPrefix:@"/"]) {
        urlString = [@"https://forum.hardware.fr" stringByAppendingString:urlString];
    }

    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPBody:self.dInputPostData];

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *redirectTask = [session dataTaskWithRequest:request
                                                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"❌ Erreur lors de la redirection : %@", error);
        } else {
            NSLog(@"✅ Statut HTTP redirection : %ld", (long)[(NSHTTPURLResponse *)response statusCode]);
            /*
            NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSUInteger length = html.length;
            NSUInteger blockSize = 1000;
            for (NSUInteger i = 0; i < length; i += blockSize) {
                NSUInteger thisBlockSize = MIN(blockSize, length - i);
                NSString *block = [html substringWithRange:NSMakeRange(i, thisBlockSize)];
                NSLog(@"🧩 Bloc %lu : %@", (unsigned long)(i / blockSize + 1), block);
            }
            */
            // Parse result
            [self parseSearchResult:data];
            
            [self.arrayData removeAllObjects];
            self.arrayData = [NSMutableArray arrayWithArray:self.arrayNewData];
            [self.arrayNewData removeAllObjects];
            
            // 🧠 Appel de la méthode UI sur le thread principal
            dispatch_async(dispatch_get_main_queue(), ^{
                NSLog(@"How many results:%ld", [self.arrayData count]);

                if ([self.arrayData count] == 0) {
                    [self.maintenanceView setText:@"Aucun résultat"];
                    [self.maintenanceView setHidden:NO];
                    [self.topicsTableView setHidden:YES];
                    [self.loadingView setHidden:YES];
                }
                else {
                    NSLog(@"Show results");
                    [self.maintenanceView setHidden:YES];
                    [self.topicsTableView setHidden:NO];
                    [self.loadingView setHidden:YES];
                }
                
                [self.topicsTableView reloadData];
                            
                [(UISegmentedControl *)[self.navigationItem.titleView.subviews objectAtIndex:0] setUserInteractionEnabled:YES];
                [self cancelFetchContent];
            });
        }
    }];
    
    [redirectTask resume];
}


- (NSString *)extractRedirectURLFromHTML:(NSString *)html {
    NSError *error = nil;
    
    // Regex pour détecter toute la balise <meta> avec refresh + URL
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"<meta[^>]*http-equiv=[\"']?refresh[\"']?[^>]*content=[\"']\\d+;\\s*url=([^\"']+)[\"'][^>]*>"
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:&error];
    
    if (error) {
        NSLog(@"❌ Erreur regex : %@", error.localizedDescription);
        return nil;
    }
    
    NSTextCheckingResult *match = [regex firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
    
    if (match && match.numberOfRanges > 1) {
        NSRange fullTagRange = [match rangeAtIndex:0];
        NSString *metaTag = [html substringWithRange:fullTagRange];
        NSLog(@"🔎 Balise <meta> détectée : %@", metaTag);
        
        NSString *redirectURL = [html substringWithRange:[match rangeAtIndex:1]];
        return redirectURL;
    }
    
    NSLog(@"⚠️ Aucune balise <meta refresh> détectée dans le HTML.");
    return nil;
}

-(void)parseSearchResult:(NSData *)contentData
{
    HTMLParser * myParser = [[HTMLParser alloc] initWithData:contentData error:NULL];
    HTMLNode * bodyNode = [myParser body];

    NSLog(@"RawContentsOfNode %@", rawContentsOfNode([bodyNode _node], [myParser _doc]));
    
    /*
    if (![bodyNode getAttributeNamed:@"id"]) {
        NSDictionary *notif;
        
        if ([[[bodyNode firstChild] tagName] isEqualToString:@"p"]) {
            
            notif = [NSDictionary dictionaryWithObjectsAndKeys:   [NSNumber numberWithInt:kMaintenance], @"status",
                     [[[bodyNode firstChild] contents] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]], @"message", nil];
            
        }
        else {
            notif = [NSDictionary dictionaryWithObjectsAndKeys:   [NSNumber numberWithInt:kNoAuth], @"status",
                     [[[bodyNode findChildWithAttribute:@"class" matchingName:@"hop" allowPartial:NO] contents] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]], @"message", nil];
            
        }
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kStatusChangedNotification object:self userInfo:notif];
        
        return;
    }

    
    //MP
    BOOL needToUpdateMP = NO;
    HTMLNode *MPNode = [bodyNode findChildOfClass:@"none"]; //Get links for cat
    NSArray *temporaryMPArray = [MPNode findChildTags:@"td"];
    
    if (temporaryMPArray.count == 3) {
        
        NSString *regExMP = @"[^.0-9]+([0-9]{1,})[^.0-9]+";
        NSString *myMPNumber = [[[temporaryMPArray objectAtIndex:1] allContents] stringByReplacingOccurrencesOfRegex:regExMP
                                                                                                          withString:@"$1"];
        
        [[HFRplusAppDelegate sharedAppDelegate] updateMPBadgeWithString:myMPNumber];
    }
    else {
        if ([self isKindOfClass:[HFRMPViewController class]]) {
            needToUpdateMP = YES;
        }
    }
    //MP

    //On remplace le numéro de page dans le titre
    NSString *regexString  = @".*page=([^&]+).*";
    NSRange   matchedRange;// = NSMakeRange(NSNotFound, 0UL);
    NSRange   searchRange = NSMakeRange(0, self.currentUrl.length);
    NSError  *error2        = NULL;
    //int numPage;
    
    matchedRange = [self.currentUrl rangeOfRegex:regexString options:RKLNoOptions inRange:searchRange capture:1L error:&error2];
    
    if (matchedRange.location == NSNotFound) {
        NSRange rangeNumPage =  [[self currentUrl] rangeOfCharactersFromSet:[NSCharacterSet decimalDigitCharacterSet] options:NSBackwardsSearch];
        self.pageNumber = [[self.currentUrl substringWithRange:rangeNumPage] intValue];
    }
    else {
        self.pageNumber = [[self.currentUrl substringWithRange:matchedRange] intValue];
        
    }
    
    //New Topic URL
    HTMLNode * forumNewTopicNode = [bodyNode findChildWithAttribute:@"id" matchingName:@"md_btn_new_topic" allowPartial:NO];
    forumNewTopicUrl = [forumNewTopicNode getAttributeNamed:@"href"];

    if(forumNewTopicUrl.length > 0) self.navigationItem.rightBarButtonItem.enabled = YES;
    //-

    //Filtres
    HTMLNode *FiltresNode =        [bodyNode findChildWithAttribute:@"class" matchingName:@"cadreonglet" allowPartial:NO];
    
    if([FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet1" allowPartial:NO]) self.forumBaseURL = [[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet1" allowPartial:NO] getAttributeNamed:@"href"];
    
    if ([[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet2" allowPartial:NO] getAttributeNamed:@"href"]) {
        if(!self.forumFavorisURL)    self.forumFavorisURL = [[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet2" allowPartial:NO] getAttributeNamed:@"href"];
        [(UISegmentedControl *)[self.navigationItem.titleView.subviews objectAtIndex:0] setEnabled:YES forSegmentAtIndex:1];
    }
    else {
        [(UISegmentedControl *)[self.navigationItem.titleView.subviews objectAtIndex:0] setEnabled:NO forSegmentAtIndex:1];
    }

    if ([[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet3" allowPartial:NO] getAttributeNamed:@"href"]) {
        if(!self.forumFlag1URL)        self.forumFlag1URL = [[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet3" allowPartial:NO] getAttributeNamed:@"href"];
        [(UISegmentedControl *)[self.navigationItem.titleView.subviews objectAtIndex:0] setEnabled:YES forSegmentAtIndex:2];
    }
    else {
        [(UISegmentedControl *)[self.navigationItem.titleView.subviews objectAtIndex:0] setEnabled:NO forSegmentAtIndex:2];
    }

    if ([[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet4" allowPartial:NO] getAttributeNamed:@"href"]) {
        if(!self.forumFlag0URL)        self.forumFlag0URL = [[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet4" allowPartial:NO] getAttributeNamed:@"href"];
        [(UISegmentedControl *)[self.navigationItem.titleView.subviews objectAtIndex:0] setEnabled:YES forSegmentAtIndex:3];
    }
    else {
        [(UISegmentedControl *)[self.navigationItem.titleView.subviews objectAtIndex:0] setEnabled:NO forSegmentAtIndex:3];
    }
    //NSLog(@"Filtres1Node %@", rawContentsOfNode([Filtres1Node _node], [myParser _doc]));
    //-- FIN Filtre

    HTMLNode * pagesTrNode = [bodyNode findChildWithAttribute:@"class" matchingName:@"fondForum1PagesHaut" allowPartial:YES];

    
    if(pagesTrNode)
    {
        HTMLNode * pagesLinkNode = [pagesTrNode findChildWithAttribute:@"class" matchingName:@"left" allowPartial:NO];
        
        //NSLog(@"pagesLinkNode %@", rawContentsOfNode([pagesLinkNode _node], [myParser _doc]));

        if (pagesLinkNode) {
            //NSLog(@"pagesLinkNode %@", rawContentsOfNode([pagesLinkNode _node], [myParser _doc]));
            
            //NSArray *temporaryNumPagesArray = [[NSArray alloc] init];
            NSArray *temporaryNumPagesArray = [pagesLinkNode children];
            
            [self setFirstPageNumber:[[[temporaryNumPagesArray objectAtIndex:2] contents] intValue]];
            
            if ([self pageNumber] == [self firstPageNumber]) {
                NSString *newFirstPageUrl = [[NSString alloc] initWithString:[self currentUrl]];
                [self setFirstPageUrl:newFirstPageUrl];
            }
            else {
                NSString *newFirstPageUrl;
                
                if ([[[temporaryNumPagesArray objectAtIndex:2] tagName] isEqualToString:@"span"]) {
                    newFirstPageUrl = [[NSString alloc] initWithString:[[[temporaryNumPagesArray objectAtIndex:2] className] decodeSpanUrlFromString2]];
                }
                else {
                    newFirstPageUrl = [[NSString alloc] initWithString:[[temporaryNumPagesArray objectAtIndex:2] getAttributeNamed:@"href"]];
                }
                
                [self setFirstPageUrl:newFirstPageUrl];
            }
            
            [self setLastPageNumber:[[[temporaryNumPagesArray lastObject] contents] intValue]];
            
            if ([self pageNumber] == [self lastPageNumber]) {
                NSString *newLastPageUrl = [[NSString alloc] initWithString:[self currentUrl]];
                [self setLastPageUrl:newLastPageUrl];
            }
            else {
                NSString *newLastPageUrl;
                
                if ([[[temporaryNumPagesArray lastObject] tagName] isEqualToString:@"span"]) {
                    newLastPageUrl = [[NSString alloc] initWithString:[[[temporaryNumPagesArray lastObject] className] decodeSpanUrlFromString2]];
                }
                else {
                    newLastPageUrl = [[NSString alloc] initWithString:[[temporaryNumPagesArray lastObject] getAttributeNamed:@"href"]];
                }
                
                [self setLastPageUrl:newLastPageUrl];
            }
            
            
            //TableFooter
            UIToolbar *tmptoolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
            
            if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0")) {
                tmptoolbar.barStyle = -1;
                
                tmptoolbar.opaque = NO;
                tmptoolbar.translucent = YES;
                
                if (tmptoolbar.subviews.count > 1)
                {
                    [[tmptoolbar.subviews objectAtIndex:1] setHidden:YES];
                }
                
                if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"10.0")) {
                    [tmptoolbar setBackgroundImage:[ThemeColors imageFromColor:[ThemeColors toolbarPageBackgroundColor:[[ThemeManager sharedManager] theme]]]
                                forToolbarPosition:UIBarPositionAny
                                        barMetrics:UIBarMetricsDefault];
                    [tmptoolbar setShadowImage:[UIImage new]
                            forToolbarPosition:UIBarPositionAny];
                    
                }
                
                
            }
            
            [tmptoolbar sizeToFit];

            UIBarButtonItem *systemItemNext = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"arrowforward"]
                                                                               style:UIBarButtonItemStyleBordered
                                                                              target:self
                                                                              action:@selector(nextPage:)];

            
            //systemItemNext.imageInsets = UIEdgeInsetsMake(2.0, 0, -2.0, 0);
            
            UIBarButtonItem *systemItemPrevious = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"arrowback"]
                                                                               style:UIBarButtonItemStyleBordered
                                                                              target:self
                                                                              action:@selector(previousPage:)];

            //systemItemPrevious.imageInsets = UIEdgeInsetsMake(2.0, 0, -2.0, 0);


            
            
            UIBarButtonItem *systemItem1 = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"arrowbegin"]
                                                                                   style:UIBarButtonItemStyleBordered
                                                                                  target:self
                                                                                  action:@selector(firstPage:)];
            
            //systemItem1.imageInsets = UIEdgeInsetsMake(2.0, 0, -2.0, 0);

            if ([self pageNumber] == [self firstPageNumber]) {
                [systemItem1 setEnabled:NO];
                [systemItemPrevious setEnabled:NO];
            }
            
            UIBarButtonItem *systemItem2 = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"arrowend"]
                                                                            style:UIBarButtonItemStyleBordered
                                                                           target:self
                                                                           action:@selector(lastPage:)];
            
            //systemItem2.imageInsets = UIEdgeInsetsMake(2.0, 0, -2.0, 0);

            if ([self pageNumber] == [self lastPageNumber]) {
                [systemItem2 setEnabled:NO];
                [systemItemNext setEnabled:NO];
            }

            UIButton *labelBtn = [UIButton buttonWithType:UIButtonTypeCustom];
            labelBtn.frame = CGRectMake(0, 0, 130, 44);
            [labelBtn addTarget:self action:@selector(choosePage) forControlEvents:UIControlEventTouchUpInside];
            [labelBtn setTitle:[NSString stringWithFormat:@"%d/%d", [self pageNumber], [self lastPageNumber]] forState:UIControlStateNormal];
            
            [[labelBtn titleLabel] setFont:[UIFont boldSystemFontOfSize:16.0]];

            if (!SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0")) {
                if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
                    [labelBtn setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
                    [labelBtn setTitleShadowColor:[UIColor darkGrayColor] forState:UIControlStateNormal];
                    [labelBtn titleLabel].shadowOffset = CGSizeMake(0.0, -1.0);
                }
                else {
                    [labelBtn setTitleColor:[UIColor colorWithRed:113/255.0 green:120/255.0 blue:128/255.0 alpha:1.0] forState:UIControlStateNormal];
                    [labelBtn setTitleShadowColor:[UIColor whiteColor] forState:UIControlStateNormal];
                    [labelBtn titleLabel].shadowColor = [UIColor whiteColor];
                    [labelBtn titleLabel].shadowOffset = CGSizeMake(0.0, 1.0);
                }
            }
            else
            {
                [labelBtn setTitleColor:[ThemeColors cellIconColor:[[ThemeManager sharedManager] theme]] forState:UIControlStateNormal];
            }
            UIBarButtonItem *systemItem3 = [[UIBarButtonItem alloc] initWithCustomView:labelBtn];
            
            //Use this to put space in between your toolbox buttons
            UIBarButtonItem *flexItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                                      target:nil
                                                                                      action:nil];
            UIBarButtonItem *fixItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace
                                                                                      target:nil
                                                                                      action:nil];
            fixItem.width = SPACE_FOR_BARBUTTON;
            
            //Add buttons to the array
            NSArray *items = [NSArray arrayWithObjects: systemItem1, fixItem, systemItemPrevious, flexItem, systemItem3, flexItem, systemItemNext, fixItem, systemItem2, nil];
            
            //release buttons
            
            

            //add array of buttons to toolbar
            [tmptoolbar setItems:items animated:NO];
            
            if ([self firstPageNumber] != [self lastPageNumber]) {
                
                
                
                if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7")) {
                    if (![self.topicsTableView viewWithTag:666777]) {
                        CGRect frame = self.topicsTableView.bounds;
                        frame.origin.y = -frame.size.height;
                        UIView* grayView = [[UIView alloc] initWithFrame:frame];
                        grayView.tag = 666777;
                        grayView.backgroundColor = [ThemeColors addMessageBackgroundColor:[[ThemeManager sharedManager] theme]];
                        [self.topicsTableView insertSubview:grayView atIndex:0];
                    }

                    [self.topicsTableView setBackgroundColor:[ThemeColors addMessageBackgroundColor:[[ThemeManager sharedManager] theme]]];
                }
                
                self.topicsTableView.tableFooterView = tmptoolbar;
            }
            else {
                self.topicsTableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
            }

            //self.aToolbar = tmptoolbar;
            
        }
        else {
            //self.aToolbar = nil;
            //NSLog(@"pas de pages");
            
        }
        
        //Gestion des pages
        NSArray *temporaryPagesArray = [pagesTrNode findChildrenWithAttribute:@"class" matchingName:@"pagepresuiv" allowPartial:YES];
            
        if(temporaryPagesArray.count != 2)
        {
            //NSLog(@"pas 2");
        }
        else {
            
            HTMLNode *nextUrlNode = [[temporaryPagesArray objectAtIndex:0] findChildWithAttribute:@"class" matchingName:@"md_cryptlink" allowPartial:YES];

            if (nextUrlNode) {
                
                self.nextPageUrl = [[nextUrlNode className] decodeSpanUrlFromString2];
                [self.view addGestureRecognizer:swipeLeftRecognizer];
                //NSLog(@"nextPageUrl = %@", self.nextPageUrl);

            }
            else {
                self.nextPageUrl = @"";
            }
            
            HTMLNode *previousUrlNode = [[temporaryPagesArray objectAtIndex:1] findChildWithAttribute:@"class" matchingName:@"md_cryptlink" allowPartial:YES];
            
            if (previousUrlNode) {
                
                self.previousPageUrl = [[previousUrlNode className] decodeSpanUrlFromString2];
                [self.view addGestureRecognizer:swipeRightRecognizer];
                //NSLog(@"previousPageUrl = %@", self.previousPageUrl);

            }
            else {
                self.previousPageUrl = @"";
            }

        }
        //-- Gestion des pages
            
        
    }
    */
    
    NSArray *temporaryTopicsArray = [bodyNode findChildrenWithAttribute:@"class" matchingName:@"sujet ligne_booleen" allowPartial:YES]; //Get links for cat

    if (temporaryTopicsArray.count == 0) {
        //NSLog(@"Aucun nouveau message %d", self.arrayDataID.count);
        NSLog(@"kNoResults");
        
        NSDictionary *notif = [NSDictionary dictionaryWithObjectsAndKeys:   [NSNumber numberWithInt:kNoResults], @"status",
                               @"Aucun message", @"message", nil];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kStatusChangedNotification object:self userInfo:notif];
        return;
    }
    else {
        NSLog(@"PARSING Found %ld results", temporaryTopicsArray.count);

    }
    
    //Date du jour
    NSDate *nowTopic = [[NSDate alloc] init];
    NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
    [dateFormat setDateFormat:@"dd-MM-yyyy"];
    int countViewed = 0;
    

    for (HTMLNode * topicNode in temporaryTopicsArray) { //Loop through all the tags
        
        @autoreleasepool {

            Topic *aTopic = [[Topic alloc] init];
            
            //Title & URL
            HTMLNode * topicTitleNode = [topicNode findChildWithAttribute:@"class" matchingName:@"sujetCase3" allowPartial:NO];

            NSString *aTopicAffix = [NSString string];
            NSString *aTopicSuffix = [NSString string];

            
            if ([[topicNode className] rangeOfString:@"ligne_sticky"].location != NSNotFound) {
                aTopicAffix = [aTopicAffix stringByAppendingString:@""];//➫ ➥▶✚
                aTopic.isSticky = YES;
            }
            if ([topicTitleNode findChildWithAttribute:@"alt" matchingName:@"closed" allowPartial:NO]) {
                aTopicAffix = [aTopicAffix stringByAppendingString:@""];
                aTopic.isClosed = YES;
            }
            
            if (aTopicAffix.length > 0) {
                aTopicAffix = [aTopicAffix stringByAppendingString:@" "];
            }

            aTopicAffix = @"";

            NSString *aTopicTitle = [[NSString alloc] initWithFormat:@"%@%@%@", aTopicAffix, [[topicTitleNode allContents] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]], aTopicSuffix];
            [aTopic setATitle:aTopicTitle];
            
            NSString *aTopicURL = [[NSString alloc] initWithString:[[topicTitleNode findChildTag:@"a"] getAttributeNamed:@"href"]];
            [aTopic setAURL:aTopicURL];

            //Answer Count
            HTMLNode * numRepNode = [topicNode findChildWithAttribute:@"class" matchingName:@"sujetCase7" allowPartial:NO];
            [aTopic setARepCount:[[numRepNode contents] intValue]];

            HTMLNode * pollImage = [topicNode findChildWithAttribute:@"src" matchingName:@"https://forum-images.hardware.fr/themes_static/images/defaut/sondage.gif" allowPartial:NO];
            if (pollImage != nil) {
                aTopic.isPoll = YES;
            }

            //Setup of Flag
            HTMLNode * topicFlagNode = [topicNode findChildWithAttribute:@"class" matchingName:@"sujetCase5" allowPartial:NO];
            HTMLNode * topicFlagLinkNode = [topicFlagNode findChildTag:@"a"];
            if (topicFlagLinkNode) {
                HTMLNode * topicFlagImgNode = [topicFlagLinkNode firstChild];

                NSString *aURLOfFlag = [[NSString alloc] initWithString:[topicFlagLinkNode getAttributeNamed:@"href"]];
                [aTopic setAURLOfFlag:aURLOfFlag];
                
                NSString *imgFlagSrc = [[NSString alloc] initWithString:[topicFlagImgNode getAttributeNamed:@"src"]];
                
                if (!([imgFlagSrc rangeOfString:@"flag0.gif"].location == NSNotFound)) {
                    [aTopic setATypeOfFlag:@"red"];
                }
                else if (!([imgFlagSrc rangeOfString:@"flag1.gif"].location == NSNotFound)) {
                    [aTopic setATypeOfFlag:@"blue"];
                }
                else if (!([imgFlagSrc rangeOfString:@"favoris.gif"].location == NSNotFound)) {
                    [aTopic setATypeOfFlag:@"yellow"];
                }
            
            }
            else {
                [aTopic setAURLOfFlag:@""];
                [aTopic setATypeOfFlag:@""];
            }

            //Viewed?
            [aTopic setIsViewed:YES];
            HTMLNode * viewedNode = [topicNode findChildWithAttribute:@"class" matchingName:@"sujetCase1" allowPartial:YES];
            HTMLNode * viewedFlagNode = [viewedNode findChildTag:@"img"];
            if (viewedFlagNode) {
                NSString *viewedFlagAlt = [viewedFlagNode getAttributeNamed:@"alt"];
            
                if ([viewedFlagAlt isEqualToString:@"On"]) {
                    [aTopic setIsViewed:NO];
                    countViewed++;
                }

            }


            //aAuthorOrInter
            HTMLNode * interNode = [topicNode findChildWithAttribute:@"class" matchingName:@"sujetCase6" allowPartial:YES];
                
            if ([[interNode findChildTag:@"a"] contents]) {
                NSString *aAuthorOrInter = [[NSString alloc] initWithFormat:@"%@", [[interNode findChildTag:@"a"] contents]];
            [aTopic setAAuthorOrInter:aAuthorOrInter];
            }
            else if ([[interNode findChildTag:@"span"] contents]) {
                NSString *aAuthorOrInter = [[NSString alloc] initWithFormat:@"%@", [[interNode findChildTag:@"span"] contents]];
                [aTopic setAAuthorOrInter:aAuthorOrInter];
            }
            else {
                [aTopic setAAuthorOrInter:@""];
            }

            //Author & Url of Last Post & Date
            HTMLNode * lastRepNode = [topicNode findChildWithAttribute:@"class" matchingName:@"sujetCase9" allowPartial:YES];
            HTMLNode * linkLastRepNode = [lastRepNode firstChild];
        
            if ([[linkLastRepNode findChildTag:@"b"] contents]) {
                NSString *aAuthorOfLastPost = [[NSString alloc] initWithFormat:@"%@", [[linkLastRepNode findChildTag:@"b"] contents]];
                [aTopic setAAuthorOfLastPost:aAuthorOfLastPost];
            }
            else {
                [aTopic setAAuthorOfLastPost:@""];
            }
            
            NSString *aURLOfLastPost = [[NSString alloc] initWithString:[linkLastRepNode getAttributeNamed:@"href"]];
            [aTopic setAURLOfLastPost:aURLOfLastPost];
            

            NSString *maDate = [linkLastRepNode contents];
            NSDateFormatter * df = [[NSDateFormatter alloc] init];
            [df setTimeZone:[NSTimeZone timeZoneWithName:@"Europe/Paris"]];
            [df setDateFormat:@"dd-MM-yyyy à HH:mm"];
            aTopic.dDateOfLastPost = [df dateFromString:maDate];
                NSTimeInterval secondsBetween = [nowTopic timeIntervalSinceDate:aTopic.dDateOfLastPost];
                int numberMinutes = secondsBetween / 60;
                int numberHours = secondsBetween / 3600;
                if (secondsBetween < 0)
                {
                    [aTopic setADateOfLastPost:[maDate substringFromIndex:13]];
                }
                else if (numberMinutes == 0)
                {
                    [aTopic setADateOfLastPost:@"il y a 1 min"];
                }
                else if (numberMinutes >= 1 && numberMinutes < 60)
                {
                    [aTopic setADateOfLastPost:[NSString stringWithFormat:@"il y a %d min",numberMinutes]];
                }
                else if (secondsBetween >= 3600 && secondsBetween < 24*3600)
                {
                    [aTopic setADateOfLastPost:[NSString stringWithFormat:@"il y a %d h",numberHours]];
                }
                else
                {
                [aTopic setADateOfLastPost:[NSString stringWithFormat:@"%@/%@/%@", [maDate substringWithRange:NSMakeRange(0, 2)]
                                      , [maDate substringWithRange:NSMakeRange(3, 2)]
                                      , [maDate substringWithRange:NSMakeRange(8, 2)]]];
            }

            //URL of Last Page & maxPage
            HTMLNode * topicLastPageNode = [[topicNode findChildWithAttribute:@"class" matchingName:@"sujetCase4" allowPartial:NO] findChildTag:@"a"];
            if (topicLastPageNode) {
                NSString *aURLOfLastPage = [[NSString alloc] initWithString:[topicLastPageNode getAttributeNamed:@"href"]];
                [aTopic setAURLOfLastPage:aURLOfLastPage];
            [aTopic setMaxTopicPage:[[topicLastPageNode contents] intValue]];

            }
            else {
                [aTopic setAURLOfLastPage:[aTopic aURL]];
            [aTopic setMaxTopicPage:1];
            
            }
            
            NSLog(@"PARSE Found topic : %@", aTopicTitle);
            [self.arrayNewData addObject:aTopic];
        }
    }
    
    if (self.status != kNoResults) {
        NSDictionary *notif = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kComplete], @"status", nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:kStatusChangedNotification object:self userInfo:notif];
    }
    
    NSLog(@"PARSE Number topics : %ld", [self.arrayNewData count]);
}

- (void)cancelFetchContent
{
    [request cancel];
}

#pragma mark -
#pragma mark ViewController Methods

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationController.navigationBar.translucent = NO;

    self.theSearchBar = [[UISearchBar alloc] init];
    theSearchBar.delegate = self;
    theSearchBar.placeholder = @"Recherche";
    theSearchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;

    if ([theSearchBar respondsToSelector:@selector(setSearchBarStyle:)]) {
        theSearchBar.searchBarStyle = UISearchBarStyleMinimal;
    }

	self.navigationItem.titleView = theSearchBar;
    self.navigationItem.titleView.frame = CGRectMake(0, 0, 320, 44);
        
	self.title = @"Recherche";
    self.stories =[[NSMutableArray alloc]init];
    self.disableViewOverlay = [[UIView alloc]
							   initWithFrame:CGRectMake(0.0f,0.0f,1000.0f,1000.0f)];
    self.disableViewOverlay.backgroundColor=[UIColor blackColor];
    self.disableViewOverlay.alpha = 0;
	
    self.disableViewOverlay.autoresizingMask = (UIViewAutoresizingFlexibleWidth);
    
	UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] 
														 initWithTarget:self action:@selector(handleTap:)];
	[self.disableViewOverlay addGestureRecognizer:tapRecognizer];
	
	[self.maintenanceView setText:@"Aucun résultat"];
    
    self.arrayData = [[NSMutableArray alloc] init];
    self.arrayNewData = [[NSMutableArray alloc] init];
}


- (void) viewWillAppear:(BOOL)animated
{
	//[self.navigationController setNavigationBarHidden:YES animated:animated];
    [super viewWillAppear:animated];
		
	if (self.messagesTableViewController) {
		//NSLog(@"viewWillAppear Topics Table View Dealloc MTV");
		
		self.messagesTableViewController = nil;
	}
}

- (void) viewWillDisappear:(BOOL)animated
{
    //[self.navigationController setNavigationBarHidden:NO animated:animated];
    [super viewWillDisappear:animated];
}

- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
	
	//[self.theSearchBar becomeFirstResponder];
}

- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
	
	if (self.topicsTableView.indexPathForSelectedRow) {
		NSLog(@"SEARCH indexPathForSelectedRow");
		//[[self.arrayData objectAtIndex:[self.topicsTableView.indexPathForSelectedRow row]] setIsViewed:YES];
		[self.topicsTableView reloadData];
	}
	
	/*[[(TopicCellView *)[topicsTableView cellForRowAtIndexPath:topicsTableView.indexPathForSelectedRow] titleLabel]setFont:[UIFont systemFontOfSize:13]];
	 [topicsTableView deselectRowAtIndexPath:topicsTableView.indexPathForSelectedRow animated:NO];*/
	
}

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
	// We don't want to do anything until the user clicks 
	// the 'Search' button.
	// If you wanted to display results as the user types 
	// you would do that here.
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    // searchBarTextDidBeginEditing is called whenever 
    // focus is given to the UISearchBar
    // call our activate method so that we can do some 
    // additional things when the UISearchBar shows.
    [self searchBar:searchBar activate:YES];
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar {
    // searchBarTextDidEndEditing is fired whenever the 
    // UISearchBar loses focus
    // We don't need to do anything here.
}

-(void)handleTap:(id)sender{
    [self searchBar:self.theSearchBar activate:NO];	
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    // Clear the search text
    // Deactivate the UISearchBar
    searchBar.text=@"";
    [self searchBar:searchBar activate:NO];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    // Do the search and show the results in tableview
    // Deactivate the UISearchBar
	
    // You'll probably want to do this on another thread
    // SomeService is just a dummy class representing some 
    // api that you are using to do the search


    [self searchBar:searchBar activate:NO];
	
	[self fetchContent];
}

// We call this when we want to activate/deactivate the UISearchBar
// Depending on active (YES/NO) we disable/enable selection and 
// scrolling on the UITableView
// Show/Hide the UISearchBar Cancel button
// Fade the screen In/Out with the disableViewOverlay and 
// simple Animations
- (void)searchBar:(UISearchBar *)searchBar activate:(BOOL) active{	
	
    self.topicsTableView.allowsSelection = !active;
    self.topicsTableView.scrollEnabled = !active;
    if (!active) {
        [disableViewOverlay removeFromSuperview];
        [searchBar resignFirstResponder];
    } else {

        self.disableViewOverlay.alpha = 0;
        [self.view addSubview:self.disableViewOverlay];
		
        [UIView beginAnimations:@"FadeIn" context:nil];
        [UIView setAnimationDuration:0.5];
        self.disableViewOverlay.alpha = 0.6;
        [UIView commitAnimations];
        
        // probably not needed if you have a details view since you 
        // will go there on selection
        NSIndexPath *selected = [self.topicsTableView 
								 indexPathForSelectedRow];
        if (selected) {
            [self.topicsTableView deselectRowAtIndexPath:selected 
											 animated:NO];
        }
    }
    [searchBar setShowsCancelButton:active animated:YES];
}

- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError {
	NSString * errorString = [NSString stringWithFormat:@"Unable to download story feed from web site (Error code %i )", [parseError code]];
	NSLog(@"error parsing XML: %@", errorString);
	NSLog(@"ERROR XML: %@", parseError);
	
	UIAlertView * errorAlert = [[UIAlertView alloc] initWithTitle:@"Error loading content" message:errorString delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[errorAlert show];
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict{			
    //NSLog(@"found this element: %@", elementName);
	currentElement = [elementName copy];
	if ([elementName isEqualToString:@"R"]) {
		// clear out our story item caches...
		item = [[NSMutableDictionary alloc] init];
		currentTitle = [[NSMutableString alloc] init];
		currentDate = [[NSMutableString alloc] init];
		currentSummary = [[NSMutableString alloc] init];
		currentLink = [[NSMutableString alloc] init];
	}
	
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName{     
	//NSLog(@"ended element: %@", elementName);
	if ([elementName isEqualToString:@"R"]) {
		// save values to an item, then store that item into the array...
		
		NSString *pattern = @"<(.|\n)*?>";

		currentTitle = (NSMutableString *)[currentTitle stringByDecodingXMLEntities];
		[item setObject:[[currentTitle stringByReplacingOccurrencesOfString:@"amp;" withString:@""] stringByReplacingOccurrencesOfRegex:pattern withString:@""] forKey:@"title"];
		//[item setObject:currentTitle forKey:@"title"];
		
		[item setObject:[currentLink stringByReplacingOccurrencesOfString:[k RealForumURL] withString:@""] forKey:@"link"];

		currentSummary = (NSMutableString *)[currentSummary stringByDecodingXMLEntities];
		[item setObject:[[currentSummary stringByReplacingOccurrencesOfString:@"amp;" withString:@""] stringByReplacingOccurrencesOfRegex:pattern withString:@""] forKey:@"summary"];
		//[item setObject:currentSummary forKey:@"summary"];
		
		[item setObject:currentDate forKey:@"date"];
		

		
		//On check si y'a page=2323
		NSString *currentUrl = [[item valueForKey:@"link"] copy];
		int pageNumber;
		
        //NSLog(@"currentUrl %@", currentUrl);
        
		NSString *regexString  = @".*page=([^&]+).*";
		NSRange   matchedRange;// = NSMakeRange(NSNotFound, 0UL);
		NSRange   searchRange = NSMakeRange(0, currentUrl.length);
		NSError  *error2        = NULL;
		
		matchedRange = [currentUrl rangeOfRegex:regexString options:RKLNoOptions inRange:searchRange capture:1L error:&error2];
		
		if (matchedRange.location == NSNotFound) {
			NSRange rangeNumPage =  [currentUrl rangeOfCharactersFromSet:[NSCharacterSet decimalDigitCharacterSet] options:NSBackwardsSearch];
            
            if (rangeNumPage.location == NSNotFound) {
                return;
            }
            
			pageNumber = [[currentUrl substringWithRange:rangeNumPage] intValue];
		}
		else {
			pageNumber = [[currentUrl substringWithRange:matchedRange] intValue];
			
		}
		//On check si y'a page=2323
		
		
		[item setObject:[NSString stringWithFormat:@"p. %d", pageNumber] forKey:@"page"];
		/**/
		[stories addObject:[item copy]];
	}
	
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string{
	//NSLog(@"found characters: %@", string);
	// save the characters for the current item...
	if ([currentElement isEqualToString:@"T"]) {
		[currentTitle appendString:string];
	} else if ([currentElement isEqualToString:@"UE"]) {
		[currentLink appendString:string];
	} else if ([currentElement isEqualToString:@"S"]) {
		[currentSummary appendString:string];
	} else if ([currentElement isEqualToString:@"pubDate"]) {
		[currentDate appendString:string];
	}
	
}

- (void)parserDidEndDocument:(NSXMLParser *)parser {
	
	NSLog(@"all done!");
	//NSLog(@"stories array has %d items", [stories count]);
	
	//NSLog(@"stories %@", stories);
	NSMutableArray *tmArr = [[NSMutableArray alloc] init];
	
	for (NSDictionary *story in stories) {
		if ([[story valueForKey:@"link"] rangeOfString:@"/liste_sujet"].location != NSNotFound) {
			[tmArr addObject:story];
			
		}
	}
	
	for (NSDictionary *story in tmArr) {
	
		[stories removeObject:story];
	}
	
	//NSLog(@"stories array has %d items", [stories count]);

	if ([stories count] == 0) {
		[self.maintenanceView setText:@"Aucun résultat"];
		[self.maintenanceView setHidden:NO];
		[self.topicsTableView setHidden:YES];
		[self.loadingView setHidden:YES];
	}
	else {
		[self.maintenanceView setHidden:YES];
		[self.topicsTableView setHidden:NO];
		[self.loadingView setHidden:YES];
	}

	
	
	[self.topicsTableView reloadData];
}


#pragma mark -
#pragma mark UITableViewDataSource Methods

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    // Return the number of rows in the section.
    return self.arrayData.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {

	static NSString *CellIdentifier = @"TopicSearchCellView";
    TopicSearchCellView *cell = (TopicSearchCellView *)[tableView dequeueReusableCellWithIdentifier:CellIdentifier];
	
    if (cell == nil)
    {
		
        [[NSBundle mainBundle] loadNibNamed:@"TopicSearchCellView" owner:self options:nil];
        cell = tmpCell;
		cell.accessoryType = UITableViewCellAccessoryNone;
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;	

		UILongPressGestureRecognizer *longPressRecognizer = [[UILongPressGestureRecognizer alloc]
															 initWithTarget:self action:@selector(handleLongPress:)];
		[cell addGestureRecognizer:longPressRecognizer];
        
        self.tmpCell = nil;
		
	}
	
	/*
	static NSString *MyIdentifier = @"MyIdentifier";
	
	UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:MyIdentifier];
	if (cell == nil) {
		cell = [[[UITableViewCell alloc] initWithFrame:CGRectZero reuseIdentifier:MyIdentifier] autorelease];
	}
	*/
	
	
	
    Topic *aTopic = [self.arrayData objectAtIndex:indexPath.row];

    NSInteger iSizeTextTopics = [[NSUserDefaults standardUserDefaults] integerForKey:@"size_text_topics"];

    UIFont *font1 = [UIFont boldSystemFontOfSize:13.0f*iSizeTextTopics/100];
    if ([aTopic isViewed]) {
        font1 = [UIFont systemFontOfSize:13.0f*iSizeTextTopics/100];
    }
    NSDictionary *arialDict = [NSDictionary dictionaryWithObject: font1 forKey:NSFontAttributeName];
    NSMutableAttributedString *aAttrString1 = [[NSMutableAttributedString alloc] initWithString:[aTopic aTitle] attributes: arialDict];
    
    UIFont *font2 = [UIFont fontWithName:@"fontello" size:15.0f*iSizeTextTopics/100];

    NSMutableAttributedString *finalString = [[NSMutableAttributedString alloc]initWithString:@""];
    
    if (aTopic.isSticky) {
        UIColor *fontsC = [UIColor colorWithHex:@"#e74c3c" alpha:1.0];
        NSDictionary *arialDict2S = [NSDictionary dictionaryWithObjectsAndKeys:font2, NSFontAttributeName, fontsC, NSForegroundColorAttributeName, nil];
        NSMutableAttributedString *aAttrString2S = [[NSMutableAttributedString alloc] initWithString:@" " attributes: arialDict2S];
        
        [finalString appendAttributedString:aAttrString2S];
    }
    
    if (aTopic.isClosed) {
//            UIColor *fontcC = [UIColor orangeColor];
        UIColor *fontcC = [UIColor colorWithHex:@"#4A4A4A" alpha:1.0];


        NSDictionary *arialDict2c = [NSDictionary dictionaryWithObjectsAndKeys:font2, NSFontAttributeName, fontcC, NSForegroundColorAttributeName, nil];
        NSMutableAttributedString *aAttrString2C = [[NSMutableAttributedString alloc] initWithString:@" " attributes: arialDict2c];
        
        [finalString appendAttributedString:aAttrString2C];
        //NSLog(@"finalString1 %@", finalString);
    }

    [finalString appendAttributedString:aAttrString1];

    cell.titleLabel.attributedText = finalString;
    cell.titleLabel.numberOfLines = 2;

    NSString* sPoll = @"";
    if (aTopic.isPoll) {
        sPoll = @" \U00002263";
    }
    if (aTopic.aRepCount == 0) {
     [cell.msgLabel setText:[NSString stringWithFormat:@"↺%@ %d", sPoll, (aTopic.aRepCount + 1)]];
    }
    else {
     [cell.msgLabel setText:[NSString stringWithFormat:@"↺%@ %d", sPoll, (aTopic.aRepCount + 1)]];
    }
    [cell.msgLabel setFont:[UIFont systemFontOfSize:13.0*iSizeTextTopics/100]];

    [cell.timeLabel setText:[NSString stringWithFormat:@"%@ - %@", [aTopic aAuthorOfLastPost], [aTopic aDateOfLastPost]]];

	// Set up the cell

//	[cell setText:[(NSString *)[[stories objectAtIndex: storyIndex] objectForKey: @"title"] stringByReplacingOccurrencesOfRegex:pattern
//																									withString:@""]];
	
    NSLog(@"Adding cell for Title %@", cell.titleLabel);
	
	return cell;
}

#pragma mark -
#pragma mark Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    // Navigation logic may go here. Create and push another view controller.
	
	//NSLog(@"did Select row Topics table views: %d", indexPath.row);
	int storyIndex = [indexPath indexAtPosition: [indexPath length] - 1];		
	
	//if (self.messagesTableViewController == nil) {
	MessagesTableViewController *aView = [[MessagesTableViewController alloc] initWithNibName:@"MessagesTableViewController" bundle:nil andUrl:[[stories objectAtIndex: storyIndex] objectForKey: @"link"]];
	self.messagesTableViewController = aView;
	
	//setup the URL
	self.messagesTableViewController.topicName = [[stories objectAtIndex: storyIndex] objectForKey: @"title"];	
	self.messagesTableViewController.isViewed = NO;	
	
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
    {
        self.navigationItem.backBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@" "
                                         style: UIBarButtonItemStylePlain
                                        target:nil
                                        action:nil];
        
        [self.navigationController pushViewController:messagesTableViewController animated:YES];
    }
    //TODO version ipad
    else
    {
        [self.navigationController pushViewController:messagesTableViewController animated:YES];
    }

}

#pragma mark -
#pragma mark LongPress delegate

-(void)handleLongPress:(UILongPressGestureRecognizer*)longPressRecognizer {
	if (longPressRecognizer.state == UIGestureRecognizerStateBegan) {
		CGPoint longPressLocation = [longPressRecognizer locationInView:self.topicsTableView];
		self.pressedIndexPath = [[self.topicsTableView indexPathForRowAtPoint:longPressLocation] copy];
        
        if (self.topicActionSheet != nil) {
            self.topicActionSheet = nil;
        }
        
		self.topicActionSheet = [[UIActionSheet alloc] initWithTitle:@":smiley-menu:"
                                                            delegate:self cancelButtonTitle:@"Annuler"
                                              destructiveButtonTitle:nil
                                                   otherButtonTitles:	@"Copier le lien",
                                 nil,
                                 nil];
		
		// use the same style as the nav bar
		self.topicActionSheet.actionSheetStyle = UIActionSheetStyleBlackTranslucent;
		
        CGPoint longPressLocation2 = [longPressRecognizer locationInView:[[[HFRplusAppDelegate sharedAppDelegate] splitViewController] view]];
        CGRect origFrame = CGRectMake( longPressLocation2.x, longPressLocation2.y, 1, 1);
        
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad)
        {
            // TODO TABBAR

            [self.topicActionSheet showFromRect:origFrame inView:[[[HFRplusAppDelegate sharedAppDelegate] splitViewController] view] animated:YES];
        }
        else
            [self.topicActionSheet showInView:[[[HFRplusAppDelegate sharedAppDelegate] rootController] view]];
        
	}
}

- (void)actionSheet:(UIActionSheet *)modalView clickedButtonAtIndex:(NSInteger)buttonIndex
{
	switch (buttonIndex)
	{
		case 0:
		{
			NSLog(@"copier lien page 1 %@", [[stories objectAtIndex: pressedIndexPath.row] objectForKey: @"link"]);
            
            UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
            pasteboard.string = [NSString stringWithFormat:@"%@%@", [k RealForumURL], [[stories objectAtIndex: pressedIndexPath.row] objectForKey: @"link"]];
            
			break;
			
		}
        default:
        {
            NSLog(@"default");
            self.pressedIndexPath = nil;
            break;
        }
			
	}
}

@end
