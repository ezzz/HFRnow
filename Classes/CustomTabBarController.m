#import "CustomTabBarController.h"
#import "ForumsTableViewController.h"
#import "FavoritesTableViewController.h"

@implementation CustomTabBarController {
    UIView *tabBarView;
    NSArray<UIViewController *> *viewControllers;
    UIViewController *currentViewController;
    NSArray<UIButton *> *tabButtons;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    self.view.backgroundColor = [UIColor whiteColor];

    ForumsTableViewController* VC1 = [[ForumsTableViewController alloc] initWithNibName:@"ForumsTableViewController" bundle:nil];
    UINavigationController *navVC1 = [[UINavigationController alloc] initWithRootViewController:VC1];
    FavoritesTableViewController* VC2 = [[FavoritesTableViewController alloc] initWithNibName:@"FavoritesTableViewController" bundle:nil];
    UINavigationController *navVC2 = [[UINavigationController alloc] initWithRootViewController:VC2];

    // Initialize View Controllers for each tab
    viewControllers = @[
        navVC1,
        navVC2,
        [self createDummyViewControllerWithTitle:@"Favorites" color:[UIColor blueColor]],
        [self createDummyViewControllerWithTitle:@"Profile" color:[UIColor purpleColor]]
    ];

    // Add all view controllers to self, but only show the first one
    for (UIViewController *vc in viewControllers) {
        [self addChildViewController:vc];
        [self.view addSubview:vc.view];
        vc.view.hidden = YES;
        [vc didMoveToParentViewController:self];
    }

    currentViewController = viewControllers[0];
    currentViewController.view.hidden = NO;

    // Create Custom Tab Bar
    [self setupTabBar];
}

#pragma mark - Create Dummy View Controller
- (UIViewController *)createDummyViewControllerWithTitle:(NSString *)title color:(UIColor *)color {
    UIViewController *vc = [[UIViewController alloc] init];
    vc.view.backgroundColor = color;
    vc.title = title;

    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(0, 0, 200, 50)];
    label.text = title;
    label.textAlignment = NSTextAlignmentCenter;
    label.font = [UIFont boldSystemFontOfSize:24];
    label.center = vc.view.center;
    label.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [vc.view addSubview:label];

    return vc;
}

#pragma mark - Setup Custom Tab Bar
- (void)setupTabBar {
    tabBarView = [[UIView alloc] init];
    tabBarView.backgroundColor = [UIColor lightGrayColor];
    tabBarView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:tabBarView];

    // Define Titles and Icons for both Active and Inactive states
    NSArray *titles = @[@"Home", @"Search", @"Favorites", @"Profile"];
    NSArray *activeIcons = @[@"house.fill", @"magnifyingglass.circle.fill", @"heart.fill", @"person.fill"];
    NSArray *inactiveIcons = @[@"house", @"magnifyingglass", @"heart", @"person"];

    NSMutableArray *buttons = [NSMutableArray array];

    for (int i = 0; i < 4; i++) {
        UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
        [button setTitle:titles[i] forState:UIControlStateNormal];
        [button setTitleColor:[UIColor blackColor] forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:12];

        // Set Initial Image
        UIImage *icon = [UIImage systemImageNamed:(i == 0 ? activeIcons[i] : inactiveIcons[i])];
        [button setImage:icon forState:UIControlStateNormal];

        // Adjust Image & Text Positioning
        button.imageEdgeInsets = UIEdgeInsetsMake(-10, 0, 0, 0);
        button.titleEdgeInsets = UIEdgeInsetsMake(30, -40, 0, 0);

        button.tag = i; // Set tag for identifying button click
        [button addTarget:self action:@selector(tabButtonTapped:) forControlEvents:UIControlEventTouchUpInside];

        button.translatesAutoresizingMaskIntoConstraints = NO;
        [tabBarView addSubview:button];
        [buttons addObject:button];
    }

    tabButtons = buttons;

    // Auto Layout Constraints for Tab Bar
    [NSLayoutConstraint activateConstraints:@[
        [tabBarView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [tabBarView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [tabBarView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [tabBarView.heightAnchor constraintEqualToConstant:70]
    ]];

    // Auto Layout for Buttons
    for (int i = 0; i < buttons.count; i++) {
        UIButton *button = buttons[i];
        [NSLayoutConstraint activateConstraints:@[
            [button.topAnchor constraintEqualToAnchor:tabBarView.topAnchor],
            [button.bottomAnchor constraintEqualToAnchor:tabBarView.bottomAnchor],
            [button.widthAnchor constraintEqualToAnchor:tabBarView.widthAnchor multiplier:0.25],
            [button.leadingAnchor constraintEqualToAnchor:(i == 0) ? tabBarView.leadingAnchor : ((UIButton*)buttons[i - 1]).trailingAnchor]
        ]];
    }
}

#pragma mark - Handle Tab Selection
- (void)tabButtonTapped:(UIButton *)sender {
    [self switchToViewControllerAtIndex:sender.tag];
    [self updateTabBarIconsForSelectedIndex:sender.tag];
}

- (void)switchToViewControllerAtIndex:(NSInteger)index {
    if (currentViewController == viewControllers[index]) return;

    // Hide previous view
    currentViewController.view.hidden = YES;

    // Show new view
    currentViewController = viewControllers[index];
    currentViewController.view.hidden = NO;
}

#pragma mark - Update Tab Bar Icons
- (void)updateTabBarIconsForSelectedIndex:(NSInteger)selectedIndex {
    NSArray *activeIcons = @[@"house.fill", @"magnifyingglass.circle.fill", @"heart.fill", @"person.fill"];
    NSArray *inactiveIcons = @[@"house", @"magnifyingglass", @"heart", @"person"];

    for (int i = 0; i < tabButtons.count; i++) {
        UIButton *button = tabButtons[i];
        UIImage *icon = [UIImage systemImageNamed:(i == selectedIndex ? activeIcons[i] : inactiveIcons[i])];
        [button setImage:icon forState:UIControlStateNormal];
    }
}
@end
