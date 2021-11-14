//
//  SmileyCodeTableViewController.h
//  SuperHFRplus
//
//  Created by ezzz on 06/12/2020.
//

#ifndef SmileyCodeTableViewController_h
#define SmileyCodeTableViewController_h

#import "SmileyAlertView.h"

@interface SmileyCodeTableViewController : UIViewController <UITableViewDelegate, UITableViewDataSource> {
}

@property (nonatomic, strong) NSMutableArray* arrCodeList;
@property (strong, nonatomic) IBOutlet UITableView *codeListTableView;
@property (strong, nonatomic) IBOutlet UIView *loadingView;

@property (nonatomic, strong) NSString* sSmileyName;
@property nsstring_block_t handlerSelectCode;

@end

#endif /* SmileyCodeTableViewController_h */
