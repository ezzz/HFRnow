#import "ObjCTopicListParser.h"

#import "HTMLParser.h"
#import "RegexKitLite.h"
#import "RangeOfCharacters.h"
#import "Topic.h"
#import "Constants.h"

static NSInteger HFRTopicPageNumberFromURLString(NSString *urlString) {
    if (urlString.length == 0) return 0;

    NSURLComponents *components = [NSURLComponents componentsWithString:urlString];
    for (NSURLQueryItem *item in components.queryItems) {
        if ([item.name isEqualToString:@"page"]) {
            NSInteger page = item.value.integerValue;
            if (page > 0) return page;
        }
    }

    NSArray<NSString *> *patterns = @[
        @"(?:\\?|&)page=(\\d+)",
        @"_(\\d+)\\.htm"
    ];

    for (NSString *pattern in patterns) {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern options:NSRegularExpressionCaseInsensitive error:nil];
        NSTextCheckingResult *match = [regex firstMatchInString:urlString options:0 range:NSMakeRange(0, urlString.length)];
        if (match.numberOfRanges < 2) continue;

        NSRange captureRange = [match rangeAtIndex:1];
        if (captureRange.location == NSNotFound) continue;

        NSInteger page = [[urlString substringWithRange:captureRange] integerValue];
        if (page > 0) return page;
    }

    return 0;
}

@implementation ObjCTopicListParsingResult

- (instancetype)init {
    self = [super init];
    if (self) {
        _topics = [NSMutableArray array];
        _currentCat = @"";
        _forumNewTopicUrl = @"";
        _pageNumber = 1;
        _firstPageNumber = 1;
        _lastPageNumber = 1;
    }
    return self;
}

@end

@implementation ObjCTopicListParser

- (ObjCTopicListParsingResult *)parseData:(NSData *)contentData currentURL:(NSString *)currentURL {
    ObjCTopicListParsingResult *result = [[ObjCTopicListParsingResult alloc] init];
    result.currentUrl = currentURL;
    HTMLParser * myParser = [[HTMLParser alloc] initWithData:contentData error:NULL];
    HTMLNode * bodyNode = [myParser body];

    //NSLog(@"RawContentsOfNode %@", rawContentsOfNode([bodyNode _node], [myParser _doc]));
    
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
        
        result.statusInfo = notif;
        return result;
    }
    
    //MP
    result.needToUpdateMP = NO;
    HTMLNode *MPNode = [bodyNode findChildOfClass:@"none"]; //Get links for cat
    NSArray *temporaryMPArray = [MPNode findChildTags:@"td"];    
    if (temporaryMPArray.count == 3) {
        result.needToUpdateMP = YES;

        NSString *regExMP = @"[^.0-9]+([0-9]{1,})[^.0-9]+";
        result.sNewMPNumber = [[[temporaryMPArray objectAtIndex:1] allContents] stringByReplacingOccurrencesOfRegex:regExMP withString:@"$1"];
    }
    
    //On remplace le numéro de page dans le titre
    NSString *regexString  = @".*page=([^&]+).*";
    NSRange   matchedRange;// = NSMakeRange(NSNotFound, 0UL);
    NSRange   searchRange = NSMakeRange(0, result.currentUrl.length);
    NSError  *error2        = NULL;
    matchedRange = [result.currentUrl rangeOfRegex:regexString options:RKLNoOptions inRange:searchRange capture:1L error:&error2];
    
    if (matchedRange.location == NSNotFound) {
        NSRange rangeNumPage =  [result.currentUrl rangeOfCharactersFromSet:[NSCharacterSet decimalDigitCharacterSet] options:NSBackwardsSearch];
        result.pageNumber = [[result.currentUrl substringWithRange:rangeNumPage] intValue];
        NSLog(@"[TopicPageTrace][ObjCTopicListParser.currentPage] source=lastDigit currentURL=%@ parsedPage=%d", result.currentUrl, result.pageNumber);
    }
    else {
        result.pageNumber = [[result.currentUrl substringWithRange:matchedRange] intValue];
        NSLog(@"[TopicPageTrace][ObjCTopicListParser.currentPage] source=query currentURL=%@ parsedPage=%d", result.currentUrl, result.pageNumber);
    }
    
    if (result.pageNumber == 0) {
        result.pageNumber = 1;
        NSLog(@"[TopicPageTrace][ObjCTopicListParser.currentPage] source=fallback currentURL=%@ parsedPage=%d", result.currentUrl, result.pageNumber);
    }
    
    // Search catégorie
    result.currentCat = @"";
    HTMLNode *headerSearchNode = [bodyNode findChildWithAttribute:@"class" matchingName:@"cadreonglet" allowPartial:NO];
    if (headerSearchNode) {
        HTMLNode *searchButtonNode = [headerSearchNode findChildWithAttribute:@"id" matchingName:@"onglet9" allowPartial:NO];
        if (searchButtonNode) {
            NSString* urlForCat = [searchButtonNode getAttributeNamed:@"href"];
            
            NSString* regexString  = @".*&cat=([^&]+).*";
            NSRange searchRange = NSMakeRange(0, urlForCat.length);
            NSRange matchedRange = [urlForCat rangeOfRegex:regexString options:RKLNoOptions inRange:searchRange capture:1L error:&error2];
            if (matchedRange.location != NSNotFound) {
                result.currentCat = [urlForCat substringWithRange:matchedRange];
            }
        }
    }
    
    // New Topic URL
    HTMLNode * forumNewTopicNode = [bodyNode findChildWithAttribute:@"id" matchingName:@"md_btn_new_topic" allowPartial:NO];
    result.forumNewTopicUrl = [forumNewTopicNode getAttributeNamed:@"href"];

    //-

    //Filtres
    HTMLNode *FiltresNode = [bodyNode findChildWithAttribute:@"class" matchingName:@"cadreonglet" allowPartial:NO];
    
    if([FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet1" allowPartial:NO]) {
        result.forumBaseURL = [[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet1" allowPartial:NO] getAttributeNamed:@"href"];
    }
    
    if ([[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet2" allowPartial:NO] getAttributeNamed:@"href"]) {
        if (!result.forumFavorisURL) {
            result.forumFavorisURL = [[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet2" allowPartial:NO] getAttributeNamed:@"href"];
        }
    }
    else {
    }

    if ([[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet3" allowPartial:NO] getAttributeNamed:@"href"]) {
        if (!result.forumFlag1URL) {
            result.forumFlag1URL = [[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet3" allowPartial:NO] getAttributeNamed:@"href"];
        }
    }
    else {
    }

    if ([[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet4" allowPartial:NO] getAttributeNamed:@"href"]) {
        if (!result.forumFlag0URL) {
            result.forumFlag0URL = [[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet4" allowPartial:NO] getAttributeNamed:@"href"];
        }
    }
    else {
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
            NSArray *temporaryNumPagesArray = [pagesLinkNode children];
            result.firstPageNumber = [[[temporaryNumPagesArray objectAtIndex:2] contents] intValue];
            NSLog(@"pageNumber %d firstpage %d", result.pageNumber, [[[temporaryNumPagesArray objectAtIndex:2] contents] intValue]);
            NSLog(@"currentUrl %@", result.currentUrl);
            if (result.pageNumber == result.firstPageNumber) {
                result.firstPageUrl = result.currentUrl;
            }
            else {
                NSString *newFirstPageUrl;
                NSLog(@"tagname %@", [[temporaryNumPagesArray objectAtIndex:2] tagName]);

                if ([[[temporaryNumPagesArray objectAtIndex:2] tagName] isEqualToString:@"span"]) {
                    newFirstPageUrl = [[NSString alloc] initWithString:[[[temporaryNumPagesArray objectAtIndex:2] className] decodeSpanUrlFromString2]];
                }
                else {
                    newFirstPageUrl = [[NSString alloc] initWithString:[[temporaryNumPagesArray objectAtIndex:2] getAttributeNamed:@"href"]];
                }
                
                result.firstPageUrl = newFirstPageUrl;
            }
            
            result.lastPageNumber = [[[temporaryNumPagesArray lastObject] contents] intValue];
            
            if (result.pageNumber == result.lastPageNumber) {
                NSString *newLastPageUrl = [[NSString alloc] initWithString:result.currentUrl];
                result.lastPageUrl = newLastPageUrl;
            }
            else {
                NSString *newLastPageUrl;
                
                if ([[[temporaryNumPagesArray lastObject] tagName] isEqualToString:@"span"]) {
                    newLastPageUrl = [[NSString alloc] initWithString:[[[temporaryNumPagesArray lastObject] className] decodeSpanUrlFromString2]];
                }
                else {
                    newLastPageUrl = [[NSString alloc] initWithString:[[temporaryNumPagesArray lastObject] getAttributeNamed:@"href"]];
                }
                
                result.lastPageUrl = newLastPageUrl;
            }
            
            


        }
        
        //Gestion des pages
        NSArray *temporaryPagesArray = [pagesTrNode findChildrenWithAttribute:@"class" matchingName:@"pagepresuiv" allowPartial:YES];
        if(temporaryPagesArray.count != 2)
        {
            //NSLog(@"SEARCH Next page PAS 2", result.nextPageUrl);
        }
        else {
            HTMLNode *nextUrlNode = [[temporaryPagesArray objectAtIndex:0] findChildWithAttribute:@"class" matchingName:@"md_cryptlink" allowPartial:YES];

            if (nextUrlNode) {
                result.nextPageUrl = [[nextUrlNode className] decodeSpanUrlFromString2];
               // NSLog(@"SEARCH Next page URL %@", result.nextPageUrl);
            }
            else {
                result.nextPageUrl = @"";
                //NSLog(@"SEARCH Next page is null", result.nextPageUrl);
            }
            
            HTMLNode *previousUrlNode = [[temporaryPagesArray objectAtIndex:1] findChildWithAttribute:@"class" matchingName:@"md_cryptlink" allowPartial:YES];
            if (previousUrlNode) {
                result.previousPageUrl = [[previousUrlNode className] decodeSpanUrlFromString2];
                //NSLog(@"previousPageUrl = %@", result.previousPageUrl);
            }
            else {
                result.previousPageUrl = @"";
            }
        }
    }
    
    NSArray *temporaryTopicsArray = [bodyNode findChildrenWithAttribute:@"class" matchingName:@"sujet ligne_booleen" allowPartial:YES]; //Get links for cat
    if (temporaryTopicsArray.count == 0) {
        //NSLog(@"Aucun nouveau message %d", result.topics.count);
        NSLog(@"kNoResults");
        NSDictionary *notif = [NSDictionary dictionaryWithObjectsAndKeys:   [NSNumber numberWithInt:kNoResults], @"status",  @"Aucun message", @"message", nil];
        result.statusInfo = notif;
        return result;
    }

    // Date du jour
    NSDate *nowTopic = [[NSDate alloc] init];
    NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
    [dateFormat setDateFormat:@"dd-MM-yyyy"];
    int countViewed = 0;
    
    // Loop through all the topic list
    for (HTMLNode * topicNode in temporaryTopicsArray) {
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

            // (Spécificque Recherche) Title & Dernier Message correspondant
            NSArray *temporaryNumPagesArray = [topicNode findChildTags:@"a"];
            if (temporaryNumPagesArray.count > 1) {
                HTMLNode* NodetemporaryNumPagesArray[1];
            }
            
            NSArray *temporaryTopicLinksArray = [topicTitleNode findChildTags:@"a"];
            if (temporaryTopicLinksArray.count > 1) {
                HTMLNode* sSearchURL = (HTMLNode*)temporaryTopicLinksArray[1];
                //NSLog(@"SEARCH sLastSearchPostURL href > %@", [sSearchURL getAttributeNamed:@"href"]);
                aTopic.sLastSearchPostURL = [sSearchURL getAttributeNamed:@"href"];
            }
            
            HTMLNode * topicExactTitleNode = [topicTitleNode findChildWithAttribute:@"class" matchingName:@"cCatTopic" allowPartial:NO];
            NSString *sExactTopicTitle = [topicExactTitleNode allContents];
            
            HTMLNode * searchContentNode = [topicTitleNode findChildWithAttribute:@"class" matchingName:@"s1" allowPartial:NO];
            if (searchContentNode) {
                aTopic.sLastSearchPostContent = [searchContentNode allContents];
                //NSLog(@"SEARCH FOUND     > %@, %@", sExactTopicTitle, aTopic.sLastSearchPostContent);
            }
            else {
                //NSLog(@"SEARCH NOT found > %@, %@", sExactTopicTitle, aTopic.sLastSearchPostContent);
            }
            NSString *resolvedTopicTitle = searchContentNode ? sExactTopicTitle : [topicTitleNode allContents];
            [aTopic setATitle: [[NSString alloc] initWithFormat:@"%@%@%@", aTopicAffix, [resolvedTopicTitle stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]], aTopicSuffix]];

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
            
                NSInteger pageNumber = HFRTopicPageNumberFromURLString(aTopic.aURLOfFlag);
                //NSLog(@"Read page of flag %@", aTopic.aURLOfFlag);
                //NSLog(@"Current page of flag %ld", pageNumber);
                NSLog(@"[TopicPageTrace][ObjCTopicListParser.flag] title=%@ flagURL=%@ topicURL=%@ parsedPage=%ld maxPage=%d",
                      aTopic.aTitle,
                      aTopic.aURLOfFlag,
                      aTopic.aURL,
                      (long)pageNumber,
                      aTopic.maxTopicPage);

                [aTopic setCurTopicPage:(int)pageNumber];
            }
            else {
                [aTopic setAURLOfFlag:@""];
                [aTopic setATypeOfFlag:@""];
            }

            //Viewed?
            [aTopic setIsViewed:YES];
            [aTopic setIsViewedFromForumAtLoad:YES];
            [aTopic setIsLocallyViewedInApp:NO];
            HTMLNode * viewedNode = [topicNode findChildWithAttribute:@"class" matchingName:@"sujetCase1" allowPartial:YES];
            HTMLNode * viewedFlagNode = [viewedNode findChildTag:@"img"];
            if (viewedFlagNode) {
                NSString *viewedFlagAlt = [viewedFlagNode getAttributeNamed:@"alt"];
            
                if ([viewedFlagAlt isEqualToString:@"On"]) {
                    [aTopic setIsViewed:NO];
                    [aTopic setIsViewedFromForumAtLoad:NO];
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
            
            [result.topics addObject:aTopic];
        }
    }
    return result;
}

@end
