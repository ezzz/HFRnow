//
//  SmileyViewController.h
//  SuperHFRplus
//
//  Created by ezzz on 09/06/2020.
//

#import <UIKit/UIKit.h>
#import "SmileyCache.h"

@class AddMessageViewController, PopupViewController, ASIHTTPRequest;

typedef enum {
    DisplayModeEnumSmileysDefault           = 0,
    DisplayModeEnumSmileysSearch            = 1,
    DisplayModeEnumSmileysFavorites         = 2,
    DisplayModeEnumTableSearch              = 3,
} DisplayModeEnum;

@interface SmileySearch : NSObject<NSCoding>
{
}

@property (nonatomic, strong) NSString *sSearchText;
@property (nonatomic, strong) NSNumber *nSearchNumber;
@property (nonatomic, strong) NSNumber *nSmileysResultNumber;
@property (nonatomic, strong) NSDate   *dLastSearch;

@end


@interface SmileyViewController : UIViewController <UITextViewDelegate, UITextFieldDelegate, UINavigationControllerDelegate, UICollectionViewDelegate, UICollectionViewDataSource, UITableViewDelegate, UITableViewDataSource, UIGestureRecognizerDelegate> {
    UICollectionView *collectionViewSmileysDefault;
}

@property (strong, nonatomic) IBOutlet UICollectionView *collectionViewSmileysDefault;
@property (strong, nonatomic) IBOutlet UICollectionView *collectionViewSmileysSearch;
@property (strong, nonatomic) IBOutlet UICollectionView *collectionViewSmileysFavorites;
@property (strong, nonatomic) IBOutlet UITextField *textFieldSmileys;
@property (strong, nonatomic) IBOutlet UIButton *btnSmileySearch;
@property (strong, nonatomic) IBOutlet UIButton *btnSmileyDefault;
@property (strong, nonatomic) IBOutlet UIButton *btnSmileyFavorites;
@property (strong, nonatomic) IBOutlet UIButton *btnReduce;
@property (strong, nonatomic) IBOutlet UIActivityIndicatorView *spinnerSmileySearch;
@property (strong, nonatomic) IBOutlet UITableView *tableViewSearch;
@property (strong, nonatomic) IBOutlet UILabel *labelNoResult;
@property (weak, nonatomic) IBOutlet UIView *viewCancelActionSmiley;
@property (weak, nonatomic) IBOutlet UILabel *labelCancelActionSmiley;
@property (weak, nonatomic) IBOutlet UIButton *btnCancelActionSmiley;

@property (strong, nonatomic) SmileyCache *smileyCache;
@property (nonatomic, strong) NSMutableArray *arrSearch;
@property (nonatomic, strong) NSMutableArray *arrTopSearchSorted;
@property (nonatomic, strong) NSMutableArray *arrLastSearchSorted;
@property (nonatomic, strong) NSArray *arrTopSearchSortedFiltered;
@property (nonatomic, strong) NSArray *arrLastSearchSortedFiltered;

@property (strong, nonatomic) NSMutableArray *arrayTmpsmileySearch;

@property ASIHTTPRequest *request;
@property ASIHTTPRequest *requestSmile;

@property AddMessageViewController* addMessageVC;
@property BOOL bModeFullScreen, bActivateSmileySearchTable;
@property DisplayModeEnum displayMode;

@property NSString* sCancelSmileyFavoriteCode;
@property BOOL bFirstLoad;
@property PopupViewController* popup;

- (void)changeDisplayMode:(DisplayModeEnum)newMode animate:(BOOL)bAnimate;
- (void)updateExpandButton;
- (float)getDisplayHeight;
- (void)actionReduce:(id)sender;
- (void)fetchSmileys;
- (void)updateTheme;

@end
