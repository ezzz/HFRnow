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
#import "ObjCTopicListParser.h"

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
#if APP_OBJC
    dispatch_async(dispatch_get_main_queue(), ^{
        [(UISegmentedControl *)[self.navigationItem.titleView.subviews objectAtIndex:0] setEnabled:bEnabled forSegmentAtIndex:index];
    });
#endif
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

    // Guard against re-enqueuing a request operation that is still running.
    if (self.request && ([self.request isExecuting] || ![self.request isFinished])) {
        [self.request cancel];
        [self setRequest:nil];
    }

    NSLog(@"fetchContent %@", [NSString stringWithFormat:@"%@%@", [k ForumURL], [self currentUrl]]);
    self.status = kIdle;
    [ASIHTTPRequest setDefaultTimeOutSeconds:kTimeoutMini];

    ASIFormDataRequest *newRequest = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@%@", [k ForumURL], [self currentUrl]]]];
    [self setRequest:newRequest];
    //[request setShouldRedirect:NO];

    [newRequest setDelegate:self];
    
    [newRequest setDidStartSelector:@selector(fetchContentStarted:)];
    [newRequest setDidFinishSelector:@selector(fetchContentComplete:)];
    [newRequest setDidFailSelector:@selector(fetchContentFailed:)];

    [self.view removeGestureRecognizer:self.swipeLeftRecognizer];
    [self.view removeGestureRecognizer:self.swipeRightRecognizer];

    [newRequest startAsynchronous];
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

#if APP_OBJC
    [(UISegmentedControl *)[self.navigationItem.titleView.subviews objectAtIndex:0] setUserInteractionEnabled:YES];
#endif
    [self cancelFetchContent];
}

- (void)fetchContentFailed:(ASIHTTPRequest *)theRequest
{
    NSLog(@"fetchContentFailed");
    [self.maintenanceView setText:@"oops :o"];
    
    //[self.loadingView setHidden:YES];
    //[self.maintenanceView setHidden:NO];
    //[self.topicsTableView setHidden:YES];
    
#if APP_OBJC
    [(UISegmentedControl *)[self.navigationItem.titleView.subviews objectAtIndex:0] setUserInteractionEnabled:YES];
#endif
    
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

-(void)parseTopicsListResult:(NSData *)contentData
{
    ObjCTopicListParsingResult *result = [[[ObjCTopicListParser alloc] init] parseData:contentData currentURL:self.currentUrl];
    [self applyTopicListParsingResult:result];
}

- (void)applyTopicListParsingResult:(ObjCTopicListParsingResult *)result
{
    if (result.statusInfo) {
        [[NSNotificationCenter defaultCenter] postNotificationName:kStatusChangedNotification object:self userInfo:result.statusInfo];
        return;
    }

    self.needToUpdateMP = result.needToUpdateMP;
    self.sNewMPNumber = result.sNewMPNumber;
    self.currentUrl = result.currentUrl;
    self.currentCat = result.currentCat;
    self.forumNewTopicUrl = result.forumNewTopicUrl;
    self.forumBaseURL = result.forumBaseURL;
    self.forumFavorisURL = result.forumFavorisURL;
    self.forumFlag1URL = result.forumFlag1URL;
    self.forumFlag0URL = result.forumFlag0URL;
    self.pageNumber = result.pageNumber;
    self.firstPageNumber = result.firstPageNumber;
    self.lastPageNumber = result.lastPageNumber;
    self.firstPageUrl = result.firstPageUrl;
    self.lastPageUrl = result.lastPageUrl;
    self.nextPageUrl = result.nextPageUrl;
    self.previousPageUrl = result.previousPageUrl;
    self.arrayNewData = [result.topics mutableCopy];

    [self setSegmentEnabled:(result.forumFavorisURL.length > 0) forSegmentAtIndex:1];
    [self setSegmentEnabled:(result.forumFlag1URL.length > 0) forSegmentAtIndex:2];
    [self setSegmentEnabled:(result.forumFlag0URL.length > 0) forSegmentAtIndex:3];

    if (result.topics.count == 0) {
        NSDictionary *notif = @{ @"status": @(kNoResults), @"message": @"Aucun message" };
        [[NSNotificationCenter defaultCenter] postNotificationName:kStatusChangedNotification object:self userInfo:notif];
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
        [[self.arrayData objectAtIndex:[self.pressedIndexPath row]] setIsLocallyViewedInApp:YES];
        
        NSArray* rowsToReload = [NSArray arrayWithObjects:self.pressedIndexPath, nil];
        [self.topicsTableView reloadRowsAtIndexPaths:rowsToReload withRowAnimation:UITableViewRowAnimationNone];
    }
    else if (self.topicsTableView.indexPathForSelectedRow && self.arrayData.count > 0 && [self.topicsTableView.indexPathForSelectedRow row] <= self.arrayData.count) {
        [[self.arrayData objectAtIndex:[self.topicsTableView.indexPathForSelectedRow row]] setIsViewed:YES];
        [[self.arrayData objectAtIndex:[self.topicsTableView.indexPathForSelectedRow row]] setIsLocallyViewedInApp:YES];
        
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
