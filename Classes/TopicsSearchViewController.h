//
//  HFRSearchViewController.h
//  HFRplus
//
//  Created by FLK on 04/11/10.
//

#import <UIKit/UIKit.h>

#import "BaseTopicsViewController.h"

@class MessagesTableViewController;
@class TopicSearchCellView;

@interface TopicsSearchViewController : BaseTopicsViewController {
}

@property(strong) UIView *disableViewOverlay;

@property (nonatomic, assign) BOOL searchVisible;
@property (nonatomic, strong) UIView *searchHeaderView;
@property (nonatomic, strong) UIView *backgroundDimView;

@property (nonatomic, strong) UIActivityIndicatorView *activityIndicator;
@property (nonatomic, strong) UILabel *loadingLabel;
@property (nonatomic, strong) UIView *locadingContainerView;
@property (nonatomic, strong) UIView *loadingView;

@property (nonatomic, strong) IBOutlet UISearchBar *textSearchBar;
@property (nonatomic, strong) UISegmentedControl *optionSearchTypeSegmentedControl;
@property (nonatomic, strong) UISegmentedControl *optionSearchInSegmentedControl;
@property (nonatomic, strong) UISegmentedControl *optionSearchFromSegmentedControl;
@property (nonatomic, strong) UILabel *optionSearchCategoryLabel;
@property (nonatomic, strong) UIButton *optionSearchCategoryButton;
@property (nonatomic, strong) UITableView *historicTableView;

@property (nonatomic, strong) UIActionSheet *topicActionSheet;

@property (nonatomic, weak) IBOutlet TopicSearchCellView *tmpCell;

@property (nonatomic, strong) NSData *dInputPostData;
// a temporary item; added to the "stories" array one at a time, and cleared for the next one
@property (nonatomic, strong)  NSMutableDictionary * item;

// it parses through the document, from top to bottom...
// we collect and cache each sub-element value, and then save each item to our array.
// we use these to track each current item, until it's ready to be added to the "stories" array
@property (nonatomic, strong)  NSString * currentElement;

- (void)searchBar:(UISearchBar *)searchBar activate:(BOOL) active;

@end
