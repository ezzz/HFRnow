//
//  IPadSplitViewController.m
//  HFRnow
//
//  Created by Bruno ARENE on 08/03/2025.
//

#import "IPadSplitViewController.h"
#import "CustomTabBarController.h"
#import "DetailNavigationViewController.h"


@implementation IPadSplitViewController

- (void)viewDidLoad {
    [super viewDidLoad];

    // Create instances of TabBar and DetailViewController
    self.leftVC = [[CustomTabBarController alloc] init];
    self.rightVC = [[DetailNavigationViewController alloc] init];

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
