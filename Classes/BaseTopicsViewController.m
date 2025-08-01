//
//  BaseTopicsTableViewController.m
//  SuperHFRplus
//
//  Created by Bruno ARENE on 18/05/2025.
//



//  BaseTopicsViewController.m
#import "BaseTopicsViewController.h"
#import "HTMLParser.h"
#import "ThemeColors.h"
#import "ThemeManager.h"
#import "ASIFormDataRequest.h"
#import "HFRplusAppDelegate.h"
#import "HFRMPViewController.h"
#import "MessagesTableViewController.h"
#import "k.h"

@implementation BaseTopicsViewController

//@synthesize request;

#pragma mark - Init

- (instancetype)init {
    self = [super init];
    if (self) {
        // Init attribute
        self.arrayData = [[NSMutableArray alloc] init];
        self.arrayNewData = [[NSMutableArray alloc] init];
        self.statusMessage = [[NSString alloc] init];
        
        self.forumNewTopicUrl = [[NSString alloc] init];
        
        self.imageForUnselectedRow = [UIImage imageNamed:@"selectedrow"];
        self.imageForSelectedRow = [UIImage imageNamed:@"unselectedrow"];
        
        self.imageForRedFlag = [UIImage imageNamed:@"Flat-RedFlag-25"];
        self.imageForYellowFlag = [UIImage imageNamed:@"Flat-YellowFlag-25"];
        self.imageForBlueFlag = [UIImage imageNamed:@"Flat-CyanFlag-25"];
        self.imageForGreyFlag = [UIImage imageNamed:@"Flat-GrayFlag-25"];
        // TODO IOS26: CRASH self.imageForGreyFlag = [self imageWithAlpha:[UIImage imageNamed:@"Flat-GrayFlag-25"] alpha:0.2];
    }
    return self;
}

#pragma mark - ViewController Methods

- (void)viewDidLoad {
    [super viewDidLoad];
    self.navigationController.navigationBar.translucent = NO;

    // Table view setup
    self.topicsTableView = [[UITableView alloc] initWithFrame:self.view.bounds style:UITableViewStylePlain];
    self.topicsTableView.delegate = self;
    self.topicsTableView.dataSource = self;
    //self.topicsTableView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:self.topicsTableView];
    
    UIView *v = [[UIView alloc] initWithFrame:CGRectZero];
    v.backgroundColor = [UIColor clearColor];
    [self.topicsTableView setTableFooterView:v];
    self.topicsTableView.sectionHeaderTopPadding = 0;

    // Maintenance label
    self.maintenanceView = [[UILabel alloc] initWithFrame:CGRectZero];
    self.maintenanceView.textAlignment = NSTextAlignmentCenter;
    self.maintenanceView.numberOfLines = 0;
    [self.view addSubview:self.maintenanceView];
        
    self.maintenanceView.backgroundColor = [UIColor clearColor];
    self.maintenanceView.hidden = YES; // masquée par défaut
    
    // Data containers
    self.arrayData = [NSMutableArray array];
    self.arrayNewData = [NSMutableArray array];
    
    // Gesture recognizer
    self.swipeRightRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeToRight:)];
    self.swipeLeftRecognizer.direction = UISwipeGestureRecognizerDirectionRight;
    [self.view addGestureRecognizer:self.swipeRightRecognizer];
    self.swipeLeftRecognizer = [[UISwipeGestureRecognizer alloc] initWithTarget:self action:@selector(handleSwipeToLeft:)];
    self.swipeLeftRecognizer.direction = UISwipeGestureRecognizerDirectionLeft;
    [self.view addGestureRecognizer:self.swipeLeftRecognizer];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(OrientationChanged)
                                                 name:UIApplicationDidChangeStatusBarOrientationNotification
                                               object:nil];
}

- (void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    [self.view becomeFirstResponder];
    Theme theme = [[ThemeManager sharedManager] theme];
    self.view.backgroundColor = self.topicsTableView.backgroundColor = self.maintenanceView.backgroundColor = [ThemeColors greyBackgroundColor:theme];
    self.topicsTableView.separatorColor = [ThemeColors cellBorderColor:theme];
    
    if (self.messagesTableViewController) {
        self.messagesTableViewController = nil;
    }
        
    if (self.pressedIndexPath) {
        self.pressedIndexPath = nil;
    }
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];
    self.topicsTableView.frame = self.view.bounds;
    self.maintenanceView.frame = self.topicsTableView.bounds;
}

- (void)handleSwipeToLeft:(UISwipeGestureRecognizer *)recognizer {
    [self nextPage:recognizer];
}

- (void)handleSwipeToRight:(UISwipeGestureRecognizer *)recognizer {
    [self previousPage:recognizer];
}

- (void)OrientationChanged
{
    if (self.topicActionAlert) {
        [self.topicActionAlert dismissViewControllerAnimated:YES completion:nil];
    }
}

#pragma mark - UITableViewDataSource
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    // Return the number of rows in the section.
    //NSLog(@"SEARCH numberOfRowsInSection %ld", self.arrayData.count);
    
    return self.arrayData.count;
}

/*
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    // A surcharger dans la sous-classe
    static NSString *CellIdentifier = @"BaseCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (!cell) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
    }
    cell.textLabel.text = @"Cellule de base";
    return cell;
}
*/

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    NSInteger iSizeTextTopics = [[NSUserDefaults standardUserDefaults] integerForKey:@"size_text_topics"];
    
    if (self.arrayData.count)
        return HEIGHT_FOR_HEADER_IN_SECTION*iSizeTextTopics/100;
    else
        return 0;
}

- (UIView *)tableView:(UITableView *)tableView viewForHeaderInSection:(NSInteger)section {
    
    //On récupère la section (forum)
    CGFloat curWidth = self.view.frame.size.width;
    NSInteger iSizeTextTopics = [[NSUserDefaults standardUserDefaults] integerForKey:@"size_text_topics"];

    //UIView globale
    UIView* customView = [[UIView alloc] initWithFrame:CGRectMake(0,0,curWidth,HEIGHT_FOR_HEADER_IN_SECTION*iSizeTextTopics/100)];
    customView.backgroundColor = [ThemeColors headSectionBackgroundColor];
    customView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
    UIView* borderView = [[UIView alloc] initWithFrame:CGRectMake(0,0,curWidth,1/[[UIScreen mainScreen] scale])];
    borderView.backgroundColor = [UIColor colorWithRed:158/255.0f green:158/255.0f blue:114/162.0f alpha:0.7];
        
    UIView* borderView2 = [[UIView alloc] initWithFrame:CGRectMake(0,HEIGHT_FOR_HEADER_IN_SECTION*iSizeTextTopics/100-1/[[UIScreen mainScreen] scale],curWidth,1/[[UIScreen mainScreen] scale])];
    borderView2.backgroundColor = [UIColor colorWithRed:158/255.0f green:158/255.0f blue:114/162.0f alpha:0.7];

    //UIButton clickable pour accéder à la catégorie
    UIButton *button = [[UIButton alloc] initWithFrame:CGRectMake(0, 0, curWidth, HEIGHT_FOR_HEADER_IN_SECTION*iSizeTextTopics/100)];
    [button setContentHorizontalAlignment:UIControlContentHorizontalAlignmentLeft];

    NSString *title = [self tableView:tableView titleForHeaderInSection:section];
    
    [button setTitleColor:[ThemeColors headSectionTextColor] forState:UIControlStateNormal];
    [button setTitle:[title uppercaseString] forState:UIControlStateNormal];
    [button.titleLabel setFont:[UIFont systemFontOfSize:14.0*iSizeTextTopics/100]];
    button.titleLabel.adjustsFontSizeToFitWidth = YES;
    [button.titleLabel setNumberOfLines:1];


    [button setTitleEdgeInsets:UIEdgeInsetsMake(2, 10, 0, 0)];

    button.translatesAutoresizingMaskIntoConstraints = NO;
    UILayoutGuide *guide = customView.safeAreaLayoutGuide;
    //Trailing
    NSLayoutConstraint *trailing =[NSLayoutConstraint
                                   constraintWithItem:button
                                   attribute:NSLayoutAttributeTrailing
                                   relatedBy:NSLayoutRelationEqual
                                   toItem:guide
                                   attribute:NSLayoutAttributeTrailing
                                   multiplier:1.0f
                                   constant:0.f];

    //Leading

    NSLayoutConstraint *leading = [NSLayoutConstraint
                                   constraintWithItem:button
                                   attribute:NSLayoutAttributeLeading
                                   relatedBy:NSLayoutRelationEqual
                                   toItem:guide
                                   attribute:NSLayoutAttributeLeading
                                   multiplier:1.0f
                                   constant:0.f];

    //Bottom
    NSLayoutConstraint *bottom =[NSLayoutConstraint
                                 constraintWithItem:button
                                 attribute:NSLayoutAttributeBottom
                                 relatedBy:NSLayoutRelationEqual
                                 toItem:customView
                                 attribute:NSLayoutAttributeBottom
                                 multiplier:1.0f
                                 constant:0.f];

    NSLayoutConstraint *top =[NSLayoutConstraint
                              constraintWithItem:button
                              attribute:NSLayoutAttributeTop
                              relatedBy:NSLayoutRelationEqual
                              toItem:customView
                              attribute:NSLayoutAttributeTop
                              multiplier:1.0f
                              constant:0.f];

    [customView addSubview:button];

    //[button.leadingAnchor constraintEqualToAnchor:guide.leadingAnchor];
    //[button.trailingAnchor constraintEqualToAnchor:guide.trailingAnchor];
    [customView addConstraint:trailing];
    [customView addConstraint:leading];
    [customView addConstraint:bottom];
    [customView addConstraint:top];
    
    return customView;
 }

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    // Return the number of sections.
    return 1;
}

- (void)setSegmentEnabled:(BOOL)bEnabled forSegmentAtIndex:(NSInteger)index{
    dispatch_async(dispatch_get_main_queue(), ^{
        [(UISegmentedControl *)[self.navigationItem.titleView.subviews objectAtIndex:0] setEnabled:bEnabled forSegmentAtIndex:index];
    });
}

#pragma mark - Data lifecycle

- (void)fetchContent
{
    [self.topicsTableView setContentOffset:CGPointZero animated:YES];
}

- (void)cancelFetchContent
{
    [self.request cancel];
    [self setRequest:nil];
}

- (void)fetchContentTrigger
{
    if (![self currentUrl]){
        [self cancelFetchContent];
        return;
    }
    NSLog(@"fetchContent %@", [NSString stringWithFormat:@"%@%@", [k ForumURL], [self currentUrl]]);
    self.status = kIdle;
    [ASIHTTPRequest setDefaultTimeOutSeconds:kTimeoutMini];

    [self setRequest:[ASIHTTPRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@%@", [k ForumURL], [self currentUrl]]]]];
    //[request setShouldRedirect:NO];

    [self.request setDelegate:self];
    
    [self.request setDidStartSelector:@selector(fetchContentStarted:)];
    [self.request setDidFinishSelector:@selector(fetchContentComplete:)];
    [self.request setDidFailSelector:@selector(fetchContentFailed:)];

    [self.view removeGestureRecognizer:self.swipeLeftRecognizer];
    [self.view removeGestureRecognizer:self.swipeRightRecognizer];

    [self.request startAsynchronous];
}

- (void)fetchContentStarted:(ASIHTTPRequest *)theRequest
{
    //[self.maintenanceView setHidden:YES];
    //[self.topicsTableView setHidden:YES];
    //[self.loadingView setHidden:NO];
    
    //--
}

- (void)fetchContentComplete:(ASIHTTPRequest *)theRequest
{
    
    [self parseTopicsListResult:[theRequest responseData]];
    
    [self.arrayData removeAllObjects];
    self.arrayData = [NSMutableArray arrayWithArray:self.arrayNewData];
    
    [self.arrayNewData removeAllObjects];
    [self.topicsTableView reloadData];
    
    if (self.nextPageUrl.length > 0) {
        [self.view addGestureRecognizer:self.swipeLeftRecognizer];
    }
    if (self.previousPageUrl.length > 0) {
        [self.view addGestureRecognizer:self.swipeRightRecognizer];
    }
    
    [(UISegmentedControl *)[self.navigationItem.titleView.subviews objectAtIndex:0] setUserInteractionEnabled:YES];
    [self cancelFetchContent];
}

- (void)fetchContentFailed:(ASIHTTPRequest *)theRequest
{
    NSLog(@"fetchContentFailed");
    [self.maintenanceView setText:@"oops :o"];
    
    //[self.loadingView setHidden:YES];
    //[self.maintenanceView setHidden:NO];
    //[self.topicsTableView setHidden:YES];
    
    
    [(UISegmentedControl *)[self.navigationItem.titleView.subviews objectAtIndex:0] setUserInteractionEnabled:YES];
    
    // Popup retry
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Ooops !" message:[theRequest.error localizedDescription]  preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* actionCancel = [UIAlertAction actionWithTitle:@"Annuler" style:UIAlertActionStyleCancel
                                                         handler:^(UIAlertAction * action) { [self cancelFetchContent]; }];
    UIAlertAction* actionRetry = [UIAlertAction actionWithTitle:@"Réessayer" style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction * action) { [self fetchContent]; }];
    [alert addAction:actionCancel];
    [alert addAction:actionRetry];
    
    [self presentViewController:alert animated:YES completion:nil];
    [[ThemeManager sharedManager] applyThemeToAlertController:alert];
}

-(void)parseTopicsListResult:(NSData *)contentData // From Search
{
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
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kStatusChangedNotification object:self userInfo:notif];
        return;
    }
    
    //MP
    self.needToUpdateMP = NO;
    HTMLNode *MPNode = [bodyNode findChildOfClass:@"none"]; //Get links for cat
    NSArray *temporaryMPArray = [MPNode findChildTags:@"td"];    
    if (temporaryMPArray.count == 3) {
        self.needToUpdateMP = YES;

        NSString *regExMP = @"[^.0-9]+([0-9]{1,})[^.0-9]+";
        self. sNewMPNumber = [[[temporaryMPArray objectAtIndex:1] allContents] stringByReplacingOccurrencesOfRegex:regExMP withString:@"$1"];
    }
    
    //On remplace le numéro de page dans le titre
    NSString *regexString  = @".*page=([^&]+).*";
    NSRange   matchedRange;// = NSMakeRange(NSNotFound, 0UL);
    NSRange   searchRange = NSMakeRange(0, self.currentUrl.length);
    NSError  *error2        = NULL;
    matchedRange = [self.currentUrl rangeOfRegex:regexString options:RKLNoOptions inRange:searchRange capture:1L error:&error2];
    
    if (matchedRange.location == NSNotFound) {
        NSRange rangeNumPage =  [[self currentUrl] rangeOfCharactersFromSet:[NSCharacterSet decimalDigitCharacterSet] options:NSBackwardsSearch];
        self.pageNumber = [[self.currentUrl substringWithRange:rangeNumPage] intValue];
    }
    else {
        self.pageNumber = [[self.currentUrl substringWithRange:matchedRange] intValue];
    }
    
    if (self.pageNumber == 0) {
        self.pageNumber = 1;
    }
    
    // Search catégorie
    self.currentCat = @"";
    HTMLNode *headerSearchNode = [bodyNode findChildWithAttribute:@"class" matchingName:@"cadreonglet" allowPartial:NO];
    if (headerSearchNode) {
        HTMLNode *searchButtonNode = [headerSearchNode findChildWithAttribute:@"id" matchingName:@"onglet9" allowPartial:NO];
        if (searchButtonNode) {
            NSString* urlForCat = [searchButtonNode getAttributeNamed:@"href"];
            
            NSString* regexString  = @".*&cat=([^&]+).*";
            NSRange searchRange = NSMakeRange(0, urlForCat.length);
            NSRange matchedRange = [urlForCat rangeOfRegex:regexString options:RKLNoOptions inRange:searchRange capture:1L error:&error2];
            if (matchedRange.location != NSNotFound) {
                self.currentCat = [urlForCat substringWithRange:matchedRange];
            }
        }
    }
    
    // New Topic URL
    HTMLNode * forumNewTopicNode = [bodyNode findChildWithAttribute:@"id" matchingName:@"md_btn_new_topic" allowPartial:NO];
    self.forumNewTopicUrl = [forumNewTopicNode getAttributeNamed:@"href"];

    //-

    //Filtres
    HTMLNode *FiltresNode = [bodyNode findChildWithAttribute:@"class" matchingName:@"cadreonglet" allowPartial:NO];
    
    if([FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet1" allowPartial:NO]) {
        self.forumBaseURL = [[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet1" allowPartial:NO] getAttributeNamed:@"href"];
    }
    
    if ([[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet2" allowPartial:NO] getAttributeNamed:@"href"]) {
        if (!self.forumFavorisURL) {
            self.forumFavorisURL = [[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet2" allowPartial:NO] getAttributeNamed:@"href"];
        }
        [self setSegmentEnabled:YES forSegmentAtIndex:1];
    }
    else {
        [self setSegmentEnabled:NO forSegmentAtIndex:1];
    }

    if ([[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet3" allowPartial:NO] getAttributeNamed:@"href"]) {
        if (!self.forumFlag1URL) {
            self.forumFlag1URL = [[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet3" allowPartial:NO] getAttributeNamed:@"href"];
        }
        [self setSegmentEnabled:YES forSegmentAtIndex:2];
    }
    else {
        [self setSegmentEnabled:NO forSegmentAtIndex:2];
    }

    if ([[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet4" allowPartial:NO] getAttributeNamed:@"href"]) {
        if (!self.forumFlag0URL) {
            self.forumFlag0URL = [[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet4" allowPartial:NO] getAttributeNamed:@"href"];
        }
        [self setSegmentEnabled:YES forSegmentAtIndex:3];
    }
    else {
        [self setSegmentEnabled:NO forSegmentAtIndex:3];
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
            [self setFirstPageNumber:[[[temporaryNumPagesArray objectAtIndex:2] contents] intValue]];
            NSLog(@"pageNumber %d firstpage %d", self.pageNumber, [[[temporaryNumPagesArray objectAtIndex:2] contents] intValue]);
            NSLog(@"currentUrl %@", self.currentUrl);
            if ([self pageNumber] == [self firstPageNumber]) {
                [self setFirstPageUrl:self.currentUrl];
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
            
            
            // TableFooter
            dispatch_async(dispatch_get_main_queue(), ^{

                UIToolbar *tmptoolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
                tmptoolbar.barStyle = -1;
                tmptoolbar.opaque = NO;
                tmptoolbar.translucent = YES;

                if (tmptoolbar.subviews.count > 1) {
                    [[tmptoolbar.subviews objectAtIndex:1] setHidden:YES];
                }

                [tmptoolbar setBackgroundImage:[ThemeColors imageFromColor:[ThemeColors headSectionBackgroundColor]] forToolbarPosition:UIBarPositionAny barMetrics:UIBarMetricsDefault];
                [tmptoolbar setShadowImage:[UIImage new] forToolbarPosition:UIBarPositionAny];
                [tmptoolbar sizeToFit];

                UIBarButtonItem *systemItemNext = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"arrowforward"]
                                                                                   style:UIBarButtonItemStylePlain
                                                                                  target:self
                                                                                  action:@selector(nextPage:)];
                
                UIBarButtonItem *systemItemPrevious = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"arrowback"]
                                                                                   style:UIBarButtonItemStylePlain
                                                                                  target:self
                                                                                  action:@selector(previousPage:)];
                
                UIBarButtonItem *systemItem1 = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"arrowbegin"]
                                                                                       style:UIBarButtonItemStylePlain
                                                                                      target:self
                                                                                      action:@selector(firstPage:)];
                
                if ([self pageNumber] == [self firstPageNumber]) {
                    [systemItem1 setEnabled:NO];
                    [systemItemPrevious setEnabled:NO];
                }
                
                UIBarButtonItem *systemItem2 = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"arrowend"]
                                                                                style:UIBarButtonItemStylePlain
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
                [labelBtn setTitle:[NSString stringWithFormat:@"%d / %d", [self pageNumber], [self lastPageNumber]] forState:UIControlStateNormal];
                
                [[labelBtn titleLabel] setFont:[UIFont boldSystemFontOfSize:16.0]];
                [labelBtn setTitleColor:[ThemeColors cellIconColor:[[ThemeManager sharedManager] theme]] forState:UIControlStateNormal];
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
                [tmptoolbar setItems:items animated:NO];
                if ([self firstPageNumber] != [self lastPageNumber]) {
                    if (![self.topicsTableView viewWithTag:666777]) {
                        CGRect frame = self.topicsTableView.bounds;
                        frame.origin.y = -frame.size.height;
                        UIView* grayView = [[UIView alloc] initWithFrame:frame];
                        grayView.tag = 666777;
                        //NOT USED ? grayView.backgroundColor = [UIColor yellowColor];// [ThemeColors headSectionBackgroundColor];//:[[ThemeManager sharedManager] theme]];
                        [self.topicsTableView insertSubview:grayView atIndex:0];
                    }

                    //NOT USED ? [self.topicsTableView setBackgroundColor:[UIColor redColor]]; //[ThemeColors headSectionBackgroundColor]];
                    self.topicsTableView.tableFooterView = tmptoolbar;
                }
                else {
                    self.topicsTableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
                }
            });

        }
        
        //Gestion des pages
        NSArray *temporaryPagesArray = [pagesTrNode findChildrenWithAttribute:@"class" matchingName:@"pagepresuiv" allowPartial:YES];
        if(temporaryPagesArray.count != 2)
        {
            //NSLog(@"SEARCH Next page PAS 2", self.nextPageUrl);
        }
        else {
            HTMLNode *nextUrlNode = [[temporaryPagesArray objectAtIndex:0] findChildWithAttribute:@"class" matchingName:@"md_cryptlink" allowPartial:YES];

            if (nextUrlNode) {
                self.nextPageUrl = [[nextUrlNode className] decodeSpanUrlFromString2];
               // NSLog(@"SEARCH Next page URL %@", self.nextPageUrl);
            }
            else {
                self.nextPageUrl = @"";
                //NSLog(@"SEARCH Next page is null", self.nextPageUrl);
            }
            
            HTMLNode *previousUrlNode = [[temporaryPagesArray objectAtIndex:1] findChildWithAttribute:@"class" matchingName:@"md_cryptlink" allowPartial:YES];
            if (previousUrlNode) {
                self.previousPageUrl = [[previousUrlNode className] decodeSpanUrlFromString2];
                //NSLog(@"previousPageUrl = %@", self.previousPageUrl);
            }
            else {
                self.previousPageUrl = @"";
            }
        }
    }
    
    NSArray *temporaryTopicsArray = [bodyNode findChildrenWithAttribute:@"class" matchingName:@"sujet ligne_booleen" allowPartial:YES]; //Get links for cat
    if (temporaryTopicsArray.count == 0) {
        //NSLog(@"Aucun nouveau message %d", self.arrayDataID.count);
        NSLog(@"kNoResults");
        NSDictionary *notif = [NSDictionary dictionaryWithObjectsAndKeys:   [NSNumber numberWithInt:kNoResults], @"status",  @"Aucun message", @"message", nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:kStatusChangedNotification object:self userInfo:notif];
        return;
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
            [aTopic setATitle: [[NSString alloc] initWithFormat:@"%@%@%@", aTopicAffix, [[topicTitleNode allContents] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]], aTopicSuffix]];

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
            
                // Read page of flag
                int pageNumber = 0;
                //Deux types d'URL:
                //https://forum.hardware.fr/hfr/Discussions/Viepratique/questions-avffuo-sujet_55667_14466.htm#t72765761
                //https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&subcat=432&post=55667&page=14466&p=1&sondage=0&owntopic=3&trash=0&trash_post=0&print=0&numreponse=0&quote_only=0&new=0&nojs=0#t72765761
                NSString *regexString  = @".*_(\\d+)\\.htm.*";
                if ([aTopic.aURLOfFlag hasPrefix:@"/forum2.php"]) {
                    regexString  = @".*page=([^&]+).*";
                }
                NSRange   matchedRange;// = NSMakeRange(NSNotFound, 0UL);
                NSRange   searchRange = NSMakeRange(0, aTopic.aURLOfFlag.length);
                NSError  *error2        = NULL;
                
                matchedRange = [aTopic.aURLOfFlag rangeOfRegex:regexString options:RKLNoOptions inRange:searchRange capture:1L error:&error2];
                
                if (matchedRange.location == NSNotFound) {
                    NSRange rangeNumPage =  [aTopic.aURLOfFlag rangeOfCharactersFromSet:[NSCharacterSet decimalDigitCharacterSet] options:NSBackwardsSearch];
                    pageNumber = [[aTopic.aURLOfFlag substringWithRange:rangeNumPage] intValue];
                }
                else {
                    pageNumber = [[aTopic.aURLOfFlag substringWithRange:matchedRange] intValue];
                    
                }
                //NSLog(@"Read page of flag %@", aTopic.aURLOfFlag);
                //NSLog(@"Current page of flag %ld", pageNumber);

                [aTopic setCurTopicPage:pageNumber];
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
            
            [self.arrayNewData addObject:aTopic];
        }
    }
}

#pragma - Tool methods

- (UIImage *)imageWithAlpha:(UIImage *)image alpha:(CGFloat)alpha {
    UIGraphicsBeginImageContextWithOptions(image.size, NO, 0.0);
    CGRect area = CGRectMake(0, 0, image.size.width, image.size.height);
    
    [image drawInRect:area blendMode:kCGBlendModeNormal alpha:alpha];
    
    UIImage *newImage = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return newImage;
}
 
- (void)pushTopic
{
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
    {
        [self.navigationController pushViewController:self.messagesTableViewController animated:YES];
    }
    else if (self.detailNavigationViewController)
    {
        self.messagesTableViewController.navigationItem.leftBarButtonItem = self.detailNavigationViewController.splitViewController.displayModeButtonItem;
        self.messagesTableViewController.navigationItem.leftItemsSupplementBackButton = YES;
        [self.detailNavigationViewController setViewControllers:[NSMutableArray arrayWithObjects:self.messagesTableViewController, nil] animated:YES];

        // Close left panel on ipad in portrait mode
        [[HFRplusAppDelegate sharedAppDelegate] hidePrimaryPanelOnIpadForSplitViewController:self.detailNavigationViewController.splitViewController];
    }
    
    [self setTopicViewed];
}


-(void)setTopicViewed {

    if (self.pressedIndexPath && self.arrayData.count > 0 && [self.pressedIndexPath row] <= self.arrayData.count) {
        [[self.arrayData objectAtIndex:[self.pressedIndexPath row]] setIsViewed:YES];
        
        NSArray* rowsToReload = [NSArray arrayWithObjects:self.pressedIndexPath, nil];
        [self.topicsTableView reloadRowsAtIndexPaths:rowsToReload withRowAnimation:UITableViewRowAnimationNone];
    }
    else if (self.topicsTableView.indexPathForSelectedRow && self.arrayData.count > 0 && [self.topicsTableView.indexPathForSelectedRow row] <= self.arrayData.count) {
        [[self.arrayData objectAtIndex:[self.topicsTableView.indexPathForSelectedRow row]] setIsViewed:YES];
        
        NSArray* rowsToReload = [NSArray arrayWithObjects:self.topicsTableView.indexPathForSelectedRow, nil];
        [self.topicsTableView reloadRowsAtIndexPaths:rowsToReload withRowAnimation:UITableViewRowAnimationNone];
    }
}

- (void)reset
{
    [self.arrayData removeAllObjects];
    [self.topicsTableView reloadData];
}

- (NSString *)newTopicTitle
{
    return @"Nouv. Sujet";
}

@end
