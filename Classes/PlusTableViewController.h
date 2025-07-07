//
//  PlusTableViewController.h
//  SuperHFRplus
//
//  Created by Bruno ARENE on 26/01/2019.
//

#ifndef PlusTableViewController_h
#define PlusTableViewController_h

#import <UIKit/UIKit.h>
#import "PlusSettingsViewController.h"
#import "CompteViewController.h"
#import "CreditsViewController.h"
#import "AQTableViewController.h"
#import "BookmarksTableViewController.h"
#import "TopicsSearchViewController.h"

@class HFRNavigationController;

@interface PlusTableViewController : UIViewController <UIActionSheetDelegate, UITableViewDelegate, UITableViewDataSource, UITextFieldDelegate, UIAlertViewDelegate, MFMailComposeViewControllerDelegate> {
    IBOutlet UITableView *plusTableView;
    int iAQBadgeNumer;
    PlusSettingsViewController *settingsViewController;
    CompteViewController *compteViewController;
    AQTableViewController *aqTableViewController;
    CreditsViewController *creditsViewController;
    TopicsSearchViewController *charteViewController;
}

@property (nonatomic, strong) IBOutlet UITableView *plusTableView;
@property int iAQBadgeNumer;
@property (nonatomic, strong) PlusSettingsViewController *settingsViewController;
@property (nonatomic, strong) TopicsSearchViewController *searchViewController;
@property (nonatomic, strong) CompteViewController *compteViewController;
@property (nonatomic, strong) AQTableViewController *aqTableViewController;
@property (nonatomic, strong) BookmarksTableViewController *bookmarksTableViewController;
@property (nonatomic, strong) CreditsViewController *creditsViewController;
@property (nonatomic, strong) CreditsViewController *charteViewController;

@property (nonatomic, strong) HFRNavigationController* detailNavigationViewController;

@end

#endif /* PlusTableViewController_h */
