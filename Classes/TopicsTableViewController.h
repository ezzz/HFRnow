//
//  TopicsTableViewController.h
//  HFRplus
//
//  Created by FLK on 06/07/10.
//

#import <UIKit/UIKit.h>
#import "BaseTopicsViewController.h"

@class MessagesTableViewController;
@class PullToRefreshErrorViewController;
@class TopicsSearchViewController;
@class HFRNavigationController;
@class ShakeView;
@class TopicCellView;

#import "AddMessageViewController.h"
#import "NewMessageViewController.h"

@interface TopicsTableViewController : BaseTopicsViewController <AddMessageViewControllerDelegate, UIPickerViewDelegate, UIPickerViewDataSource, UIActionSheetDelegate, UIGestureRecognizerDelegate, UITableViewDelegate, UITableViewDataSource, UIPopoverPresentationControllerDelegate, UIAdaptivePresentationControllerDelegate> {
	
}


@property (nonatomic, strong) UIPickerView *myPickerView;
@property (nonatomic, strong) NSArray *pickerViewArray;
@property (nonatomic, strong) UIActionSheet *actionSheet;
@property (nonatomic, strong) UISegmentedControl  *subCatSegmentedControl;
@property (nonatomic, strong) NSString *forumName;
@property (nonatomic, strong) NSString *forumNewTopicUrl;
@property (nonatomic, strong) NSString *forumBaseURL;
@property (nonatomic, strong) NSString *forumFavorisURL;
@property (nonatomic, strong) NSString *forumFlag1URL;
@property (nonatomic, strong) NSString *forumFlag0URL;

@property (nonatomic, strong) TopicsSearchViewController *topicSearchViewController;
@property (nonatomic, strong) PullToRefreshErrorViewController *errorVC;

@property (nonatomic, weak) IBOutlet TopicCellView *tmpCell;

@property (nonatomic, strong) UISwipeGestureRecognizer *swipeLeftRecognizer;
@property (nonatomic, strong) UISwipeGestureRecognizer *swipeRightRecognizer;

@property (strong, nonatomic) ASIHTTPRequest *request;

@property int selectedFlagIndex;

@property (nonatomic, strong) id popover;

- (instancetype)init;
- (instancetype)initWithFlag:(int)flag;


- (void)loadDataInTableView:(NSData *)contentData;
- (void)reset;
- (void)shakeHappened:(ShakeView*)view;

- (void)showPicker:(id)sender;
- (CGRect)pickerFrameWithSize:(CGSize)size;
- (void)dismissActionSheet;
- (void)segmentFilterAction;

- (void)cancelFetchContent;
- (void)fetchContentStarted:(ASIHTTPRequest *)theRequest;
- (void)fetchContentComplete:(ASIHTTPRequest *)theRequest;
- (void)fetchContentFailed:(ASIHTTPRequest *)theRequest;

- (void)chooseTopicPage;
- (void)newTopic;

- (void)setTopicViewed;
- (void)pushTopic;

- (void)test;

@end
