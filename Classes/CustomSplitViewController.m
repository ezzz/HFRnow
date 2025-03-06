//
//  CustomViewController.m
//  HFRnow
//
//  Created by Bruno ARENE on 02/03/2025.
//

#import "CustomSplitViewController.h"
#import "ForumsTableViewController.h"
#import "DetailNavigationViewController.h"
#import "ThemeColors.h"
#import "ThemeManager.h"
@interface CustomSplitViewController ()

@end

@implementation CustomSplitViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor whiteColor];

    // Initialize child view controllers
    ForumsTableViewController* forumVC = [[ForumsTableViewController alloc] init];
    self.leftVC = [[UINavigationController alloc] initWithRootViewController:forumVC];
    UINavigationBarAppearance *app = [UINavigationBarAppearance new];
    app.backgroundColor = [ThemeColors navBackgroundColor:[[ThemeManager sharedManager] theme]];
    self.leftVC.navigationBar.scrollEdgeAppearance = self.leftVC.navigationBar.standardAppearance = app;

    
    self.rightVC = [[DetailNavigationViewController alloc] init];
    forumVC.detailNavigationVC = (DetailNavigationViewController*)self.rightVC;

    // Add as child view controllers
    [self addChildViewController:self.leftVC];
    [self addChildViewController:self.rightVC];

    // Add their views
    [self.view addSubview:self.leftVC.view];
    [self.view addSubview:self.rightVC.view];

    // Inform child controllers they have been added
    [self.leftVC didMoveToParentViewController:self];
    [self.rightVC didMoveToParentViewController:self];

    // Setup layout using Auto Layout
    self.leftVC.view.translatesAutoresizingMaskIntoConstraints = NO;
    self.rightVC.view.translatesAutoresizingMaskIntoConstraints = NO;

    [NSLayoutConstraint activateConstraints:@[
        // Left View
        [self.leftVC.view.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.leftVC.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.leftVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.leftVC.view.widthAnchor constraintEqualToAnchor:self.view.widthAnchor multiplier:0.5],

        // Right View
        [self.rightVC.view.leadingAnchor constraintEqualToAnchor:self.leftVC.view.trailingAnchor],
        [self.rightVC.view.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.rightVC.view.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.rightVC.view.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
}

@end
