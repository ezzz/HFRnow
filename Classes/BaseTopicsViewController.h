//
//  BaseTopicsTableViewController.h
//  SuperHFRplus
//
//  Created by Bruno ARENE on 18/05/2025.
//


//  BaseTopicsViewController.h
#import <UIKit/UIKit.h>
#import "PageViewController.h"
#import "Constants.h"

@class MessagesTableViewController;
@class ASIFormDataRequest;
@class ASIHTTPRequest;

@interface BaseTopicsViewController : PageViewController <UITableViewDelegate, UITableViewDataSource, UIActionSheetDelegate>

// Views
@property (nonatomic, strong) UITableView *topicsTableView;
@property (nonatomic, strong) UILabel *maintenanceView;
@property (nonatomic, strong) UIAlertController *topicActionAlert;

@property (nonatomic, strong) NSMutableArray *arrayData;
@property (nonatomic, strong) NSMutableArray *arrayNewData;

@property (nonatomic, strong) MessagesTableViewController *messagesTableViewController;
@property (nonatomic, strong) HFRNavigationController *detailNavigationViewController;

@property (nonatomic, strong) UISwipeGestureRecognizer *swipeLeftRecognizer;
@property (nonatomic, strong) UISwipeGestureRecognizer *swipeRightRecognizer;

// Data Attributes
@property STATUS status;
@property BOOL needToUpdateMP;
@property NSString* sNewMPNumber;
@property (nonatomic, strong) NSIndexPath *pressedIndexPath;
@property (nonatomic, strong) NSString *statusMessage;
@property (strong, nonatomic) ASIFormDataRequest *request;

@property (nonatomic, strong) UIImage *imageForUnselectedRow;
@property (nonatomic, strong) UIImage *imageForSelectedRow;
@property (nonatomic, strong) UIImage *imageForRedFlag;
@property (nonatomic, strong) UIImage *imageForYellowFlag;
@property (nonatomic, strong) UIImage *imageForBlueFlag;
@property (nonatomic, strong) UIImage *imageForGreyFlag;

@property (nonatomic, strong) NSString *forumName;
@property (nonatomic, strong) NSString *forumNewTopicUrl;
@property (nonatomic, strong) NSString *forumBaseURL;
@property (nonatomic, strong) NSString *forumFavorisURL;
@property (nonatomic, strong) NSString *forumFlag1URL;
@property (nonatomic, strong) NSString *forumFlag0URL;

// Methods
- (void)cancelFetchContent;
- (void)fetchContentTrigger;
- (void)fetchContentStarted:(ASIHTTPRequest *)theRequest;
- (void)fetchContentComplete:(ASIHTTPRequest *)theRequest;
- (void)fetchContentFailed:(ASIHTTPRequest *)theRequest;
- (void)parseTopicsListResult:(NSData *)contentData;
- (void)reset;
- (NSString *)newTopicTitle;
- (void)setTopicViewed;
- (void)pushTopic;


@end
