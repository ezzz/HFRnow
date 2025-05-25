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

@interface BaseTopicsViewController : PageViewController <UITableViewDelegate, UITableViewDataSource, UIActionSheetDelegate>

// Views
@property (nonatomic, strong) UITableView *topicsTableView;
@property (nonatomic, strong) UIView *loadingView;
@property (nonatomic, strong) UILabel *maintenanceView;

@property (nonatomic, strong) UIAlertController *topicActionAlert;


@property (nonatomic, strong) NSMutableArray *arrayData;
@property (nonatomic, strong) NSMutableArray *arrayNewData;

@property (nonatomic, strong) MessagesTableViewController *messagesTableViewController;
@property (nonatomic, strong) HFRNavigationController *detailNavigationViewController;

@property (nonatomic, strong) NSIndexPath *pressedIndexPath;
@property STATUS status;
@property (nonatomic, strong) NSString *statusMessage;
@property (strong, nonatomic) ASIFormDataRequest *request;

@property (nonatomic, strong) UIImage *imageForUnselectedRow;
@property (nonatomic, strong) UIImage *imageForSelectedRow;
@property (nonatomic, strong) UIImage *imageForRedFlag;
@property (nonatomic, strong) UIImage *imageForYellowFlag;
@property (nonatomic, strong) UIImage *imageForBlueFlag;
@property (nonatomic, strong) UIImage *imageForGreyFlag;


@end
