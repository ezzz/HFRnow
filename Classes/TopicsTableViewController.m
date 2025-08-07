//
//  TopicsTableViewController.m
//  HFRplus
//
//  Created by FLK on 06/07/10.
//

#import "HFRplusAppDelegate.h"
#import "ASIHTTPRequest+Tools.h"
#import "Constants.h"
#import "HTMLParser.h"
#import "ShakeView.h"
#import "TopicsTableViewController.h"
#import "MessagesTableViewController.h"
#import "HFRMPViewController.h"
#import "BaseTopicsViewController.h"
#import "TopicCellView.h"
#import "Topic.h"
#import "SubCatTableViewController.h"
#import "UIScrollView+SVPullToRefresh.h"
#import "AideViewController.h"
#import "ThemeColors.h"
#import "ThemeManager.h"
#import "SmileyAlertView.h"
#import "PullToRefreshErrorViewController.h"
#import "TopicsSearchViewController.h"

@implementation TopicsTableViewController
@synthesize arrayData, arrayNewData;
@synthesize messagesTableViewController, detailNavigationViewController, topicSearchViewController, errorVC;
@synthesize pressedIndexPath;
@synthesize imageForSelectedRow, imageForUnselectedRow;
@synthesize imageForRedFlag, imageForYellowFlag, imageForBlueFlag, imageForGreyFlag;
@synthesize request;
@synthesize myPickerView, pickerViewArray, actionSheet, topicActionAlert, subCatSegmentedControl;
@synthesize tmpCell;
@synthesize status, statusMessage, maintenanceView, selectedFlagIndex;
@synthesize popover = _popover;



#pragma mark - Init

- (instancetype)init {
    self = [super init];
    if (self) {
        self.selectedFlagIndex = 0;
    }
    return self;
}

- (instancetype)initWithFlag:(int)flag {
    self = [super init];
    if (self) {
        self.selectedFlagIndex = flag;
    }
    return self;
}

#pragma mark - ViewController Methods

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = self.forumName;

    NSLog(@"self nav %@", self.navigationController);

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(StatusChanged:)
                                                 name:kStatusChangedNotification
                                               object:nil];
    
    //Title View
    self.navigationItem.titleView = [[UIView alloc] init];//WithFrame:CGRectMake(0, 0, 120, self.navigationController.navigationBar.frame.size.height - 14)];
    self.navigationItem.backBarButtonItem = [[UIBarButtonItem alloc] initWithTitle:@"Retour" style:UIBarButtonItemStyleBordered target:nil action:nil];
    self.navigationItem.backBarButtonItem.title = @" ";
    
    //Filter Control
    UISegmentedControl* segmentedControl = [[UISegmentedControl alloc] initWithItems: [NSArray arrayWithObjects: @"Tous", @"Favoris", @"Suivis", @"Lus", nil]];
    [segmentedControl setWidth:38.0f forSegmentAtIndex:0];
    [segmentedControl setWidth:44.0f forSegmentAtIndex:1];
    [segmentedControl setWidth:38.0f forSegmentAtIndex:2];
    [segmentedControl setWidth:32.0f forSegmentAtIndex:3];
    UIFont *font = [UIFont systemFontOfSize:10.0f];
    NSDictionary *attributes = [NSDictionary dictionaryWithObject:font forKey:UITextAttributeFont];
    [segmentedControl setTitleTextAttributes:attributes forState:UIControlStateNormal];
    [segmentedControl setUserInteractionEnabled:NO];
    [segmentedControl addTarget:self action:@selector(segmentFilterAction) forControlEvents:UIControlEventValueChanged];
    NSDictionary *selectedAttributes = @{NSForegroundColorAttributeName: [UIColor systemBackgroundColor]};
    [segmentedControl setTitleTextAttributes:selectedAttributes forState:UIControlStateSelected];
    [self.navigationItem.titleView insertSubview:segmentedControl atIndex:1];

    
    
    //SubCats Control
    if (self.pickerViewArray.count) {
        UISegmentedControl *segmentedControl2 = [[UISegmentedControl alloc] initWithItems: [NSArray arrayWithObjects: [UIImage imageNamed:@"all_categories"], nil]];
        [segmentedControl2 addTarget:self action:@selector(showPicker:) forControlEvents:UIControlEventValueChanged];
        segmentedControl2.segmentedControlStyle = UISegmentedControlStyleBar;
        segmentedControl2.momentary = YES;
        segmentedControl2.frame = CGRectMake(segmentedControl.frame.size.width + 15, 0, segmentedControl2.frame.size.width, segmentedControl2.frame.size.height);
        segmentedControl.frame = CGRectMake(5, 0, segmentedControl.frame.size.width, segmentedControl.frame.size.height);
        CGRect oldSegFrame = segmentedControl2.frame;
        oldSegFrame.size.width -= 10;
        segmentedControl2.frame = oldSegFrame;
        [self.navigationItem.titleView insertSubview:segmentedControl2 atIndex:1];
        self.navigationItem.titleView.frame = CGRectMake(0, 0, segmentedControl.frame.size.width + 20 + segmentedControl2.frame.size.width, segmentedControl.frame.size.height);
        segmentedControl.autoresizingMask = (UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin);
        segmentedControl2.autoresizingMask = (UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin);
        self.navigationItem.titleView.autoresizingMask = (UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin);
        self.subCatSegmentedControl = segmentedControl2;
    }
    else {
        segmentedControl.frame = CGRectMake(5, 0, segmentedControl.frame.size.width, segmentedControl.frame.size.height);
        self.navigationItem.titleView.frame = CGRectMake(0, 0, segmentedControl.frame.size.width, segmentedControl.frame.size.height);
        segmentedControl.autoresizingMask = (UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin);
        self.navigationItem.titleView.autoresizingMask = (UIViewAutoresizingFlexibleHeight | UIViewAutoresizingFlexibleTopMargin | UIViewAutoresizingFlexibleBottomMargin);
    }

    UIBarButtonItem *buttontBarItemRight = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:self action:@selector(newTopic)];
    buttontBarItemRight.enabled = NO;
    
    self.navigationItem.rightBarButtonItems = [[NSMutableArray alloc] initWithObjects:buttontBarItemRight, nil];
    
    if (self.pickerViewArray.count) {
        actionSheet = [[UIActionSheet alloc] initWithTitle:nil delegate:nil cancelButtonTitle:nil destructiveButtonTitle:nil otherButtonTitles:nil];
        [actionSheet setBackgroundColor:[UIColor whiteColor]];
        myPickerView = [[UIPickerView alloc] initWithFrame:CGRectZero];
        myPickerView.showsSelectionIndicator = YES;
        myPickerView.dataSource = self;
        myPickerView.delegate = self;
        [myPickerView setBackgroundColor:[UIColor colorWithRed:0 green:0 blue:0 alpha:0.03]];
        [actionSheet addSubview:myPickerView];
        
        UISegmentedControl *closeButton = [[UISegmentedControl alloc] initWithItems:[NSArray arrayWithObject:@"Retour"]];
        closeButton.momentary = YES;
        closeButton.frame = CGRectMake(10, 7.0f, 55.0f, 30.0f);
        closeButton.segmentedControlStyle = UISegmentedControlStyleBar;
        closeButton.tintColor = [UIColor blackColor];
        [closeButton addTarget:self action:@selector(dismissActionSheet) forControlEvents:UIControlEventValueChanged];
        [actionSheet addSubview:closeButton];
        
        UISegmentedControl *confirmButton = [[UISegmentedControl alloc] initWithItems:[NSArray arrayWithObject:@"Valider"]];
        confirmButton.momentary = YES;
        confirmButton.tag = 546;
        confirmButton.frame = CGRectMake(255, 7.0f, 55.0f, 30.0f);
        confirmButton.segmentedControlStyle = UISegmentedControlStyleBar;
        confirmButton.tintColor = [UIColor colorWithRed:60/255.f green:136/255.f blue:230/255.f alpha:1.00];
        [confirmButton addTarget:self action:@selector(loadSubCat) forControlEvents:UIControlEventValueChanged];
        [actionSheet addSubview:confirmButton];
    }
    
    [(UISegmentedControl *)[self.navigationItem.titleView.subviews objectAtIndex:0] setSelectedSegmentIndex:self.selectedFlagIndex];
    [self goFlag];
}

- (void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    Theme theme = [[ThemeManager sharedManager] theme];
    self.topicsTableView.pullToRefreshView.backgroundColor = [ThemeColors greyBackgroundColor:theme];
    self.topicsTableView.pullToRefreshView.arrowColor = [ThemeColors cellTextColor:theme];
    self.topicsTableView.pullToRefreshView.textColor = [ThemeColors cellTextColor:theme];
    self.topicsTableView.pullToRefreshView.activityIndicatorViewStyle = [ThemeColors activityIndicatorViewStyle];
    if (self.errorVC) {
        [self.errorVC applyTheme];
    }

    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(loadSubCat) name:@"SubCatSelected" object:nil];
    
    if (self.topicSearchViewController) {
        self.topicSearchViewController = nil;
    }
    [self.topicsTableView reloadData];
}


-(void)searchForum
{
    self.topicSearchViewController = [[TopicsSearchViewController alloc] init];
    self.topicSearchViewController.currentCat = self.currentCat;
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    { // iPad
        if (self.detailNavigationViewController)
        {
            [self.detailNavigationViewController setViewControllers:[NSMutableArray arrayWithObjects:self.topicSearchViewController, nil] animated:YES];
        }
    }
    else { // iPhone
        [self.navigationController pushViewController:self.topicSearchViewController animated:YES];
        //self.navigationItem.backBarButtonItem.title = @"Topics";
    }
}

- (void)newTopic
{
	//[[HFRplusAppDelegate sharedAppDelegate] openURL:[NSString stringWithFormat:@"http://forum.hardware.fr%@", forumNewTopicUrl]];

	NewMessageViewController *editMessageViewController = [[NewMessageViewController alloc]
															initWithNibName:@"AddMessageViewController" bundle:nil];
	editMessageViewController.delegate = self;
	[editMessageViewController setUrlQuote:[NSString stringWithFormat:@"%@%@", [k ForumURL], self.forumNewTopicUrl]];
	editMessageViewController.title = [self newTopicTitle];
	// Create the navigation controller and present it modally.
	HFRNavigationController *navigationController = [[HFRNavigationController alloc]
													initWithRootViewController:editMessageViewController];

    navigationController.modalPresentationStyle = UIModalPresentationFullScreen;
	[self presentModalViewController:navigationController animated:YES];
	
	// The navigation controller is now owned by the current view controller
	// and the root view controller is owned by the navigation controller,
	// so both objects should be released to prevent over-retention.

}

- (void)loadSubCat
{
    [_popover dismissPopoverAnimated:YES];
    
    [self dismissModalViewControllerAnimated:YES];

    
	//NSLog(@"curName %@", self.forumName);
	
	//NSLog(@"newName %@", [[pickerViewArray objectAtIndex:[myPickerView selectedRowInComponent:0]] aTitle]);

	if (![self.forumName isEqualToString:[[pickerViewArray objectAtIndex:[myPickerView selectedRowInComponent:0]] aTitle]]) {
		//NSLog(@"On switch");
        
		self.currentUrl = [[pickerViewArray objectAtIndex:[myPickerView selectedRowInComponent:0]] aURL];
		self.forumName = [[pickerViewArray objectAtIndex:[myPickerView selectedRowInComponent:0]] aTitle];
		self.forumBaseURL = self.currentUrl;

		self.forumFavorisURL = nil;
		self.forumFlag1URL = nil;
		self.forumFlag0URL = nil;	
			
		self.title = self.forumName;
		
		if ([(UISegmentedControl *)[self.navigationItem.titleView.subviews objectAtIndex:0] selectedSegmentIndex] == 0) {
			[self segmentFilterAction];
		}
		else {
			[(UISegmentedControl *)[self.navigationItem.titleView.subviews objectAtIndex:0] setSelectedSegmentIndex:0];
            [self segmentFilterAction];
		}
	}
	else {
		
	}
	
	[self dismissActionSheet];
}

-(void)StatusChanged:(NSNotification *)notification {
    
    if ([[notification object] class] != [self class]) {
        //NSLog(@"KO");
        return;
    }
    
    NSDictionary *notif = [notification userInfo];
    
    self.status = [[notif valueForKey:@"status"] intValue];
    
    //NSLog(@"StatusChanged %d = %u", self.childViewControllers.count, self.status);
    
    //on vire l'eventuel header actuel
    if (self.childViewControllers.count > 0) {
        [[self.childViewControllers objectAtIndex:0] removeFromParentViewController];
        self.topicsTableView.tableHeaderView = nil;
    }
    
    if (self.status == kComplete || self.status == kIdle) {
        //NSLog(@"COMPLETE %d", self.childViewControllers.count);
        
    }
    else {
        self.errorVC = [[PullToRefreshErrorViewController alloc] initWithNibName:nil bundle:nil andDico:notif];
        [self addChildViewController:self.errorVC];
        
        self.topicsTableView.tableHeaderView = self.errorVC.view;
        [self.errorVC sizeToFit];
        [self.errorVC applyTheme];
    }
}

- (void)goFlag {
    [(UISegmentedControl *)[self.navigationItem.titleView.subviews objectAtIndex:0] setUserInteractionEnabled:NO];

	switch (self.selectedFlagIndex) {
		case 0:
			self.currentUrl = self.forumBaseURL;
			break;
		case 1:
			self.currentUrl = self.forumFavorisURL;   
			break;			
		case 2:
			self.currentUrl = self.forumFlag1URL;
			break;
		case 3:
			self.currentUrl = self.forumFlag0URL;  
			break;			
		default:
			self.currentUrl = self.forumBaseURL;  
			break;
	}
    
    
    // setup pull-to-refresh
    //dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{

    __weak TopicsTableViewController *self_ = self;
    [self.topicsTableView addPullToRefreshWithActionHandler:^{
        //NSLog(@"=== BEGIN");
        [self_ fetchContentTrigger];
        //NSLog(@"=== END");
    }];

    [self fetchContent];
    //});
    //[self fetchContent];
}

- (void)segmentFilterAction
{
	switch ([(UISegmentedControl *)[self.navigationItem.titleView.subviews objectAtIndex:0] selectedSegmentIndex]) {
		case 0:
            self.selectedFlagIndex = 0;
			break;
		case 1:
            self.selectedFlagIndex = 1;            
			break;			
		case 2:
            self.selectedFlagIndex = 2;            
			break;
		case 3:
            self.selectedFlagIndex = 3;            
			break;			
		default:
            self.selectedFlagIndex = 0;            
			break;
	}
    
	[self goFlag];
}


- (void)viewDidDisappear:(BOOL)animated
{
    [super viewDidDisappear:animated];
	[self.view resignFirstResponder];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:@"SubCatSelected" object:nil];
}

#pragma mark - Data lifecycle

- (void)fetchContent {
    [super fetchContent];
    [self.topicsTableView triggerPullToRefresh];
}

- (void)cancelFetchContent {
    [super cancelFetchContent];
    [self.topicsTableView.pullToRefreshView stopAnimating];
}

- (void)fetchContentTrigger {
    [super fetchContentTrigger];
}

- (void)fetchContentStarted:(ASIHTTPRequest *)theRequest {
    [super fetchContentStarted:theRequest];
}

- (void)fetchContentComplete:(ASIHTTPRequest *)theRequest {
    [super fetchContentComplete:theRequest];
    
    // UI update
    if (self.status != kNoResults) {
        NSDictionary *notif = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kComplete], @"status", nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:kStatusChangedNotification object:self userInfo:notif];
    }
    
    if (self.needToUpdateMP == YES) {
        [[HFRplusAppDelegate sharedAppDelegate] updateMPBadgeWithString:self.sNewMPNumber];
    }
    
    if (self.forumNewTopicUrl.length > 0) {
        self.navigationItem.rightBarButtonItem.enabled = YES;
    }

    [self.topicsTableView.pullToRefreshView stopAnimating];
    [self.topicsTableView.pullToRefreshView setLastUpdatedDate:[NSDate date]];
}

- (void)fetchContentFailed:(ASIHTTPRequest *)theRequest {
    [super fetchContentFailed:theRequest];
    [self.topicsTableView.pullToRefreshView stopAnimating];
}

#pragma mark - AddMessage Delegate

- (void)addMessageViewControllerDidFinish:(AddMessageViewController *)controller {
    //NSLog(@"addMessageViewControllerDidFinish %@", self.editFlagTopic);
	
	//[self setEditFlagTopic:nil];
	[self dismissModalViewControllerAnimated:YES];
}

- (void)addMessageViewControllerDidFinishOK:(AddMessageViewController *)controller {
	//NSLog(@"addMessageViewControllerDidFinishOK");
	
	[self dismissModalViewControllerAnimated:YES];
	[self shakeHappened:nil];
	[self.navigationController popToViewController:self animated:NO];
}

#pragma mark - Table view data source
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	return [[self forumName] stringByAppendingString:[NSString stringWithFormat:@" p.%d", [self pageNumber]]];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSInteger iSizeTextTopics = [[NSUserDefaults standardUserDefaults] integerForKey:@"size_text_topics"];
    return 62.0*iSizeTextTopics/100;
}

// Customize the appearance of table view cells.
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {

    //NSLog(@"SEARCH cellForRowAtIndexPath %ld", indexPath.row);
    
	static NSString *CellIdentifier = @"ApplicationCell";
    
    TopicCellView *cell = (TopicCellView *)[tableView dequeueReusableCellWithIdentifier:CellIdentifier];
	
    if (cell == nil)
    {

        [[NSBundle mainBundle] loadNibNamed:@"TopicCellView" owner:self options:nil];
        cell = tmpCell;
		cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
		cell.selectionStyle = UITableViewCellSelectionStyleBlue;	

		UILongPressGestureRecognizer *longPressRecognizer = [[UILongPressGestureRecognizer alloc] 
															 initWithTarget:self action:@selector(handleLongPress:)];
		[cell addGestureRecognizer:longPressRecognizer];
		
        self.tmpCell = nil;
		
	}
		 

	Topic *aTopic = [arrayData objectAtIndex:indexPath.row];
    cell.topicViewed = [aTopic isViewed];

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
    
    if (aTopic.curTopicPage > 0 && aTopic.curTopicPage <= aTopic.maxTopicPage) {
        [cell.msgLabel setText:[NSString stringWithFormat:@"⚑%@ %d / %d", sPoll, aTopic.curTopicPage, aTopic.maxTopicPage]];
	}
	else {
        [cell.msgLabel setText:[NSString stringWithFormat:@"⚑%@ %d", sPoll, aTopic.maxTopicPage]];
	}
    [cell.msgLabel setFont:[UIFont systemFontOfSize:13.0*iSizeTextTopics/100]];

    // Time label 
	[cell.timeLabel setText:[NSString stringWithFormat:@"%@ - %@", [aTopic aAuthorOfLastPost], [aTopic aDateOfLastPost]]];
    [cell.timeLabel setFont:[UIFont systemFontOfSize:11.0*iSizeTextTopics/100]];



	//Flag
    if (aTopic.aTypeOfFlag.length > 0) {
		
		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
		
		CGRect frame = CGRectMake(0.0, 0.0, 45, 50);
		button.frame = frame;	// match the button's size with the image size

        if (aTopic.isViewed) {
            [button setBackgroundImage:self.imageForGreyFlag forState:UIControlStateNormal];
            [button setBackgroundImage:self.imageForGreyFlag forState:UIControlStateHighlighted];
        }
        else {
            if([[aTopic aTypeOfFlag] isEqualToString:@"red"]) {
                [button setBackgroundImage:imageForRedFlag forState:UIControlStateNormal];
                [button setBackgroundImage:imageForRedFlag forState:UIControlStateHighlighted];
            }
            else if ([[aTopic aTypeOfFlag] isEqualToString:@"blue"]) {
                [button setBackgroundImage:imageForBlueFlag forState:UIControlStateNormal];
                [button setBackgroundImage:imageForBlueFlag forState:UIControlStateHighlighted];
            }
            else if ([[aTopic aTypeOfFlag] isEqualToString:@"yellow"]) {
                [button setBackgroundImage:imageForYellowFlag forState:UIControlStateNormal];
                [button setBackgroundImage:imageForYellowFlag forState:UIControlStateHighlighted];
            }
        }
        
		// set the button's target to this table view controller so we can interpret touch events and map that to a NSIndexSet
		[button addTarget:self action:@selector(accessoryButtonTapped:withEvent:) forControlEvents:UIControlEventTouchUpInside];

        //[button setBackgroundColor:[UIColor greenColor]];
		
        cell.accessoryView = button;
	}
	else {
		
		UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
	
		//CGRect frame = CGRectMake(0.0, 0.0, imageForSelectedRow.size.width, imageForSelectedRow.size.height);
		CGRect frame = CGRectMake(0.0, 0.0, 45, 50);
		button.frame = frame;	// match the button's size with the image size
		
		[button setBackgroundImage:imageForSelectedRow forState:UIControlStateNormal];
		[button setBackgroundImage:imageForUnselectedRow forState:UIControlStateHighlighted];
		[button setUserInteractionEnabled:NO];
        //[button setBackgroundColor:[UIColor blueColor]];

		cell.accessoryView = button;
		
	}
	//Flag
    return cell;
	
}

- (void) accessoryButtonTapped: (UIControl *) button withEvent: (UIEvent *) event
{
    NSIndexPath * indexPath = [self.topicsTableView indexPathForRowAtPoint: [[[event touchesForView: button] anyObject] locationInView: self.topicsTableView]];
    if ( indexPath == nil )
        return;
	else {
		[self setPressedIndexPath:indexPath];
		//self.pressedIndexPath = [indexPath autorelease];
	}

    Topic* topic = [arrayData objectAtIndex:indexPath.row];
    self.messagesTableViewController = [[MessagesTableViewController alloc] initWithNibName:@"MessagesTableViewController" bundle:nil andUrl:topic.aURLOfFlag displaySeparator:YES];
	self.messagesTableViewController.topicName = topic.aTitle;
	self.messagesTableViewController.isViewed = topic.isViewed;

	[self pushTopic];
}

-(void)handleLongPress:(UILongPressGestureRecognizer*)longPressRecognizer {
	if (longPressRecognizer.state == UIGestureRecognizerStateBegan) {
		CGPoint longPressLocation = [longPressRecognizer locationInView:self.topicsTableView];
		self.pressedIndexPath = [[self.topicsTableView indexPathForRowAtPoint:longPressLocation] copy];
				
        if (self.topicActionAlert != nil) {
            self.topicActionAlert = nil;
        }
        
        NSMutableArray *arrayActionsMessages = [NSMutableArray array];
        [arrayActionsMessages addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"Première page", @"firstPageAction", nil] forKeys:[NSArray arrayWithObjects:@"title", @"code", nil]]];
        [arrayActionsMessages addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"Dernière page", @"lastPageAction", nil] forKeys:[NSArray arrayWithObjects:@"title", @"code", nil]]];
        [arrayActionsMessages addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"Dernière réponse", @"lastPostAction", nil] forKeys:[NSArray arrayWithObjects:@"title", @"code", nil]]];
        [arrayActionsMessages addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"Page numéro...", @"chooseTopicPage", nil] forKeys:[NSArray arrayWithObjects:@"title", @"code", nil]]];
        [arrayActionsMessages addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"Copier le lien", @"copyLinkAction", nil] forKeys:[NSArray arrayWithObjects:@"title", @"code", nil]]];
        
        topicActionAlert = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];

        for( NSDictionary *dico in arrayActionsMessages) {
            [topicActionAlert addAction:[UIAlertAction actionWithTitle:[dico valueForKey:@"title"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                if ([self respondsToSelector:NSSelectorFromString([dico valueForKey:@"code"])])
                {
                    //[self performSelector:];
                    [self performSelectorOnMainThread:NSSelectorFromString([dico valueForKey:@"code"]) withObject:nil waitUntilDone:NO];
                }
                else {
                    NSLog(@"CRASH not respondsToSelector %@", [dico valueForKey:@"code"]);
                    
                    [self performSelectorOnMainThread:NSSelectorFromString([dico valueForKey:@"code"]) withObject:nil waitUntilDone:NO];
                }
            }]];
        }
				

        if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
            [topicActionAlert addAction:[UIAlertAction actionWithTitle:@"Annuler" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                [self dismissViewControllerAnimated:YES completion:nil];
            }]];
        }
        else   {
            // Required for UIUserInterfaceIdiomPad
            CGPoint pointLocation = [longPressRecognizer locationInView:self.view];
            CGRect origFrame = CGRectMake( pointLocation.x, pointLocation.y, 1, 1);
            topicActionAlert.popoverPresentationController.sourceView = self.view;
            topicActionAlert.popoverPresentationController.sourceRect = origFrame;
            topicActionAlert.popoverPresentationController.backgroundColor = [ThemeColors alertBackgroundColor:[[ThemeManager sharedManager] theme]];
        }
        UIImpactFeedbackGenerator *generator = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
        [generator prepare];
        [self presentViewController:topicActionAlert animated:YES completion:nil];
        [[ThemeManager sharedManager] applyThemeToAlertController:topicActionAlert];
        [generator impactOccurred];
    }

}

-(void)firstPageAction {
    MessagesTableViewController *aView = [[MessagesTableViewController alloc] initWithNibName:@"MessagesTableViewController" bundle:nil andUrl:[[arrayData objectAtIndex:pressedIndexPath.row] aURL]];
    self.messagesTableViewController = aView;
    
    self.messagesTableViewController.topicName = [[arrayData objectAtIndex:pressedIndexPath.row] aTitle];
    self.messagesTableViewController.isViewed = [[arrayData objectAtIndex:pressedIndexPath.row] isViewed];
    
    [self pushTopic];
}

-(void)lastPageAction{
    MessagesTableViewController *aView = [[MessagesTableViewController alloc] initWithNibName:@"MessagesTableViewController" bundle:nil andUrl:[[arrayData objectAtIndex:pressedIndexPath.row] aURLOfLastPage]];
    self.messagesTableViewController = aView;
    
    self.messagesTableViewController.topicName = [[arrayData objectAtIndex:pressedIndexPath.row] aTitle];
    self.messagesTableViewController.isViewed = [[arrayData objectAtIndex:pressedIndexPath.row] isViewed];
    
    [self pushTopic];
    //[self.navigationController pushViewController:messagesTableViewController animated:YES];
    //NSLog(@"url pressed last page: %@", [[arrayData objectAtIndex:pressedIndexPath.row] aURLOfLastPage]);
}

-(void)lastPostAction{
    
    MessagesTableViewController *aView = [[MessagesTableViewController alloc] initWithNibName:@"MessagesTableViewController" bundle:nil andUrl:[[arrayData objectAtIndex:pressedIndexPath.row] aURLOfLastPost]];
    self.messagesTableViewController = aView;
    
    self.messagesTableViewController.topicName = [[arrayData objectAtIndex:pressedIndexPath.row] aTitle];
    self.messagesTableViewController.isViewed = [[arrayData objectAtIndex:pressedIndexPath.row] isViewed];
    
    [self pushTopic];
    //NSLog(@"url pressed last post: %@", [[arrayData objectAtIndex:pressedIndexPath.row] aURLOfLastPost]);
}

-(void)copyLinkAction {
    NSLog(@"copier lien page 1");
    
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = [NSString stringWithFormat:@"%@%@", [k RealForumURL], [[arrayData objectAtIndex:pressedIndexPath.row] aURL]];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleAlert];
    NSMutableAttributedString * message = [[NSMutableAttributedString alloc] initWithString:@"Lien copié dans le presse-papiers"];
    [message addAttribute:NSForegroundColorAttributeName value:[ThemeColors textColor:[[ThemeManager sharedManager] theme]] range:(NSRange){0, [message.string length]}];
    [alert setValue:message forKey:@"attributedMessage"];
    [self presentViewController:alert animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:nil];
        });
    }];
    [[ThemeManager sharedManager] applyThemeToAlertController:alert];
    
}


-(void)test {
    AideViewController *avc = [[AideViewController alloc] initWithNibName:@"AideViewController" bundle:nil];
    [avc awakeFromNib];
    
    //[rightMessageController removeFromParentViewController];
    
    NSLog(@"avc %@", avc);
    
    [self.navigationController pushViewController:avc animated:YES];
}



#pragma mark -
#pragma mark chooseTopicPage

-(void)chooseTopicPage {
    //NSLog(@"chooseTopicPage Topics");
    
    UIAlertController * alertController = [UIAlertController alertControllerWithTitle: nil
                                                                              message: nil
                                                                       preferredStyle:UIAlertControllerStyleAlert];
    NSMutableAttributedString * message = [[NSMutableAttributedString alloc] initWithString:@"Aller à la page"];
    [message addAttribute:NSForegroundColorAttributeName value:[ThemeColors textColor:[[ThemeManager sharedManager] theme]] range:(NSRange){0, [message.string length]}];
    [alertController setValue:message forKey:@"attributedTitle"];
    [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = [NSString stringWithFormat:@"(numéro entre 1 et %d)", [[arrayData objectAtIndex:pressedIndexPath.row] maxTopicPage]];
        [[ThemeManager sharedManager] applyThemeToTextField:textField];
        textField.textAlignment = NSTextAlignmentCenter;
        textField.delegate = self;
        [textField addTarget:self action:@selector(textFieldTopicDidChange:) forControlEvents:UIControlEventEditingChanged];
        textField.keyboardAppearance = [ThemeColors keyboardAppearance:[[ThemeManager sharedManager] theme]];
        textField.keyboardType = UIKeyboardTypeNumberPad;
        
    }];
    
    [alertController addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSArray * textfields = alertController.textFields;
        UITextField * pagefield = textfields[0];
        int pageNumber = [[pagefield text] intValue];
        [self gotoPageNumber:pageNumber];
        
    }]];
    [alertController addAction:[UIAlertAction actionWithTitle:@"Annuler"
                                                        style:UIAlertActionStyleCancel
                                                      handler:^(UIAlertAction * _Nonnull action) {
                                                          [alertController dismissViewControllerAnimated:YES completion:nil];
                                                      }]];
    
    [[ThemeManager sharedManager] applyThemeToAlertController:alertController];
    [self presentViewController:alertController animated:YES completion:^{
        if([[ThemeManager sharedManager] theme] == ThemeDark){
            for (UIView* textfield in alertController.textFields) {
                UIView *container = textfield.superview;
                UIView *effectView = container.superview.subviews[0];
                
                if (effectView && [effectView class] == [UIVisualEffectView class]){
                    container.backgroundColor = [UIColor clearColor];
                    [effectView removeFromSuperview];
                }
            }
        }
    }];
    
    
    
    
}

-(void)textFieldTopicDidChange:(id)sender {
	//NSLog(@"textFieldDidChange %d %@", [[(UITextField *)sender text] intValue], sender);	
	
	
	if ([[(UITextField *)sender text] length] > 0) {
		int val; 
		if ([[NSScanner scannerWithString:[(UITextField *)sender text]] scanInt:&val]) {
			//NSLog(@"int %d %@ %@", val, [(UITextField *)sender text], [NSString stringWithFormat:@"%d", val]);
			
			if (![[(UITextField *)sender text] isEqualToString:[NSString stringWithFormat:@"%d", val]]) {
				//NSLog(@"pas int");
				[sender setText:[NSString stringWithFormat:@"%d", val]];
			}
			else if ([[(UITextField *)sender text] intValue] < 1) {
				//NSLog(@"ERROR WAS %d", [[(UITextField *)sender text] intValue]);
				[sender setText:[NSString stringWithFormat:@"%d", 1]];
				//NSLog(@"ERROR NOW %d", [[(UITextField *)sender text] intValue]);
				
			}
			else if ([[(UITextField *)sender text] intValue] > [[arrayData objectAtIndex:pressedIndexPath.row] maxTopicPage]) {
				//NSLog(@"ERROR WAS %d", [[(UITextField *)sender text] intValue]);
				[sender setText:[NSString stringWithFormat:@"%d", [[arrayData objectAtIndex:pressedIndexPath.row] maxTopicPage]]];
				//NSLog(@"ERROR NOW %d", [[(UITextField *)sender text] intValue]);
				
			}	
			else {
				//NSLog(@"OK");
			}
		}
		else {
			[sender setText:@""];
		}
		
		
	}
}


-(void)gotoPageNumber:(int)number{
        //NSLog(@"goto topic page %d", [[pageNumberField text] intValue]);
        NSString * newUrl = [[NSString alloc] initWithString:[[arrayData objectAtIndex:pressedIndexPath.row] aURL]];
        newUrl = [newUrl stringByReplacingOccurrencesOfString:@"_1.htm" withString:[NSString stringWithFormat:@"_%d.htm", number]];
        newUrl = [newUrl stringByReplacingOccurrencesOfString:@"page=1&" withString:[NSString stringWithFormat:@"page=%d&",number]];
        newUrl = [newUrl stringByRemovingAnchor];
        
		MessagesTableViewController *aView = [[MessagesTableViewController alloc] initWithNibName:@"MessagesTableViewController" bundle:nil andUrl:newUrl];
		self.messagesTableViewController = aView;
        self.messagesTableViewController.topicName = [[arrayData objectAtIndex:pressedIndexPath.row] aTitle];
        self.messagesTableViewController.isViewed = [[arrayData objectAtIndex:pressedIndexPath.row] isViewed];	
        
        [self pushTopic];
}


#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    // Navigation logic may go here. Create and push another view controller.
    Topic* selectedTopic = [arrayData objectAtIndex:indexPath.row];
    NSString *sURL = selectedTopic.aURL; // URL par défaut sur onglet TOUS = first post of first page
    BOOL bDisplaySeparator = NO;
    if (selectedTopic.aTypeOfFlag.length > 0) {
        sURL = selectedTopic.aURLOfFlag;  // URL par défaut sur les autres onglet
        bDisplaySeparator = YES;
    }
    else if (self.selectedFlagIndex > 0) {
        sURL = selectedTopic.aURLOfLastPost; // Pour les favoris et drapeaux
    }
    /* Ne fonctionne pas si on a un drapeau N page avant la fin qu'on ne lit pas les N. Il ne faut pas aller à la fin du topic.
    else if (selectedTopic.hasNewMessageInTopic && selectedTopic.isViewed) { // On va a la fin que si on a déjà lu le topic (il avait de nouveau messages au chargement)
        sURL = selectedTopic.aURLOfLastPost;
    }*/
    MessagesTableViewController *aView = [[MessagesTableViewController alloc] initWithNibName:@"MessagesTableViewController" bundle:nil andUrl:sURL displaySeparator:bDisplaySeparator];
    self.messagesTableViewController = aView;
    [self.messagesTableViewController setTopicName:[[arrayData objectAtIndex:indexPath.row] aTitle]];
	self.messagesTableViewController.isViewed = [[arrayData objectAtIndex:indexPath.row] isViewed];	
    
    [self pushTopic];
}

#pragma mark -
#pragma mark UIPickerViewDelegate

- (void)pickerView:(UIPickerView *)pickerView didSelectRow:(NSInteger)row inComponent:(NSInteger)component
{
	if (pickerView == myPickerView)	// don't show selection for the custom picker
	{
		// report the selection to the UI label
		//label.text = [NSString stringWithFormat:@"%@ - %d",
		//			  [pickerViewArray objectAtIndex:[pickerView selectedRowInComponent:0]],
		//			  [pickerView selectedRowInComponent:1]];
		
		//NSLog(@"%@", [pickerViewArray objectAtIndex:[pickerView selectedRowInComponent:0]]);
	}
}

- (NSString *)pickerView:(UIPickerView *)pickerView titleForRow:(NSInteger)row forComponent:(NSInteger)component
{
	NSString *returnStr = @"";
	
	if (row == 0) {
		//NSString *returnStr = @"";

	}
	else {
		returnStr = @"- ";
	}

	
	// note: custom picker doesn't care about titles, it uses custom views
	if (pickerView == myPickerView)
	{
		if (component == 0)
		{
			returnStr = [returnStr stringByAppendingString:[[pickerViewArray objectAtIndex:row] aTitle]];
		}
	}
	
	return returnStr;
}
/*
 - (CGFloat)pickerView:(UIPickerView *)pickerView widthForComponent:(NSInteger)component
 {
 CGFloat componentWidth = 0.0;
 
 if (component == 0)
 componentWidth = 240.0;	// first column size is wider to hold names
 else
 componentWidth = 40.0;	// second column is narrower to show numbers
 
 return componentWidth;
 }
 */
- (CGFloat)pickerView:(UIPickerView *)pickerView rowHeightForComponent:(NSInteger)component
{
	return 40.0;
}

- (NSInteger)pickerView:(UIPickerView *)pickerView numberOfRowsInComponent:(NSInteger)component
{
	return [pickerViewArray count];
}

- (NSInteger)numberOfComponentsInPickerView:(UIPickerView *)pickerView
{
    //NSLog(@"NOC");
	return 1;
}


// return the picker frame based on its size, positioned at the bottom of the page
- (CGRect)pickerFrameWithSize:(CGSize)size
{
	//CGRect screenRect = [[UIScreen mainScreen] applicationFrame];
	CGRect pickerRect = CGRectMake(	0.0,
								   40,
								    self.view.frame.size.width,
								   size.height);
	
	
	return pickerRect;
}

-(void)dismissActionSheet {
	[actionSheet dismissWithClickedButtonIndex:0 animated:YES];
}

-(UIViewController *)presentationController:(UIPresentationController *)controller viewControllerForAdaptivePresentationStyle:(UIModalPresentationStyle)style   {
    
    UINavigationController *uvc = [[UINavigationController alloc] initWithRootViewController:controller.presentedViewController];
    return uvc;
    
}

- (UIModalPresentationStyle)adaptivePresentationStyleForPresentationController:(UIPresentationController *)controller {
    return UIModalPresentationNone;
}

-(void)showPicker:(id)sender {

    SubCatTableViewController *subCatTableViewController = [[SubCatTableViewController alloc] initWithStyle:UITableViewStylePlain];
    subCatTableViewController.suPicker = myPickerView;
    subCatTableViewController.arrayData = pickerViewArray;
    subCatTableViewController.notification = @"SubCatSelected";
    
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"8")) {
        subCatTableViewController.modalPresentationStyle = UIModalPresentationPopover;
        UIPopoverPresentationController *pc = [subCatTableViewController popoverPresentationController];
        pc.permittedArrowDirections = UIPopoverArrowDirectionAny;
        pc.delegate = self;
        pc.sourceView = self.subCatSegmentedControl;
        pc.sourceRect = CGRectMake(0, 0, 45, 35);

        [self presentViewController:subCatTableViewController animated:YES completion:nil];
    }
    else {
        self.popover = nil;
        self.popover = [[UIPopoverController alloc] initWithContentViewController:subCatTableViewController];
        CGRect origFrame = [(UISegmentedControl *)sender frame];
        [_popover presentPopoverFromRect:origFrame inView:self.navigationItem.titleView permittedArrowDirections:UIPopoverArrowDirectionAny animated:YES];
    }
}

@end

