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
@class TopicCellView;
@class Topic;
@class Forum;

@interface TopicsTableViewController : BaseTopicsViewController <UIPickerViewDelegate, UIPickerViewDataSource, UIActionSheetDelegate, UIGestureRecognizerDelegate, UITableViewDelegate, UITableViewDataSource, UIPopoverPresentationControllerDelegate, UIAdaptivePresentationControllerDelegate> {
	
}


@property (nonatomic, strong) UIPickerView *myPickerView;
@property (nonatomic, strong) NSArray *pickerViewArray;
@property (nonatomic, strong) UIActionSheet *actionSheet;
@property (nonatomic, strong) UISegmentedControl  *subCatSegmentedControl;

#if !APP_SWIFT
@property (nonatomic, strong) TopicsSearchViewController *topicSearchViewController;
#endif
@property (nonatomic, strong) PullToRefreshErrorViewController *errorVC;

@property (nonatomic, weak) IBOutlet TopicCellView *tmpCell;

//@property (strong, nonatomic) ASIHTTPRequest *request;

@property int selectedFlagIndex;

@property (nonatomic, strong) id popover;

- (instancetype)init;
- (instancetype)initWithFlag:(int)flag;
- (void)reset;

// SWIFT
@property (nonatomic, copy) void (^completion)(NSArray<Topic *> *topics, NSError *error);
- (void)fetchContentForForum:(Forum *)forum
                   flagIndex:(NSInteger)flagIndex
                  completion:(void (^)(NSArray<Topic *> *topics, NSError *error))completion;
- (void)fetchContentForForum:(Forum *)forum
                   flagIndex:(NSInteger)flagIndex
                     pageURL:(NSString *)pageURL
                  completion:(void (^)(NSArray<Topic *> *topics, NSError *error))completion;

@end
