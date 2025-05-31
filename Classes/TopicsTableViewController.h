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

@property (nonatomic, strong) TopicsSearchViewController *topicSearchViewController;
@property (nonatomic, strong) PullToRefreshErrorViewController *errorVC;

@property (nonatomic, weak) IBOutlet TopicCellView *tmpCell;

//@property (strong, nonatomic) ASIHTTPRequest *request;

@property int selectedFlagIndex;

@property (nonatomic, strong) id popover;

- (instancetype)init;
- (instancetype)initWithFlag:(int)flag;
- (void)reset;
- (void)pushTopic;

 /*
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

- (void)test;*/

@end
