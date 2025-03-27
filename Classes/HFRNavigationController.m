//
//  HFRNavigationController.m
//  HFRplus
//
//  Created by FLK on 19/07/12.
//

#import "HFRNavigationController.h"

@implementation HFRNavigationController


- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    NSLog(@"viewDidLoad HFR HFR NavControll.");
    
    self.view.backgroundColor = [UIColor systemPinkColor]; // Set background color to blue
    self.title = @"Blue Screen"; // Set a title for the navigation bar

    /*
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(userThemeDidChange)
                                                 name:kThemeChangedNotification
                                               object:nil];
    if (SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0")) {
        UITapGestureRecognizer* tapRecon = [[UITapGestureRecognizer alloc]
                                            initWithTarget:self action:@selector(navigationBarDoubleTap:)];
        tapRecon.numberOfTapsRequired = 1;
        tapRecon.numberOfTouchesRequired = 2;
        [self.navigationBar addGestureRecognizer:tapRecon];
        self.navigationBar.barStyle = [ThemeColors barStyle:[[ThemeManager sharedManager] theme]];
    }
    */
    // Create the root detail view controller
    UIViewController *detailVC = [[UIViewController alloc] init];
    detailVC.view.backgroundColor = [UIColor orangeColor]; // Detail View (Orange)
    detailVC.title = @"Detail";

    // Add button to show master in portrait mode
    detailVC.navigationItem.leftBarButtonItem = self.splitViewController.displayModeButtonItem;
    detailVC.navigationItem.leftItemsSupplementBackButton = YES;

    // Set the root view controller of this navigation controller
    [self setViewControllers:@[detailVC] animated:NO];

}


@end
