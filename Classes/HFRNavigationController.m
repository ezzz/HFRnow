//
//  HFRNavigationController.m
//  HFRplus
//
//  Created by FLK on 19/07/12.
//

#import "HFRNavigationController.h"
#import "HFRplusAppDelegate.h"
#import "ThemeColors.h"
#import "ThemeManager.h"
#import "UINavigationBar+Helper.h"
#import "InAppSettingsKit+Theme.h"

@implementation HFRNavigationController

// Default construtor
- (HFRNavigationController*)init {
    self = [super init];
    if (self) {
        self.isDetailView = NO;  // Default value set in initializer
    }
    return self;
}

- (HFRNavigationController*)initAsDetailView {
    self = [super init];
    if (self) {
        self.isDetailView = YES;
    }
    return self;
}


- (void)viewDidLoad
{
    [super viewDidLoad];
	// Do any additional setup after loading the view.
    NSLog(@"viewDidLoad HFR HFR NavControll.");
    

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(userThemeDidChange)
                                                 name:kThemeChangedNotification
                                               object:nil];
    UITapGestureRecognizer* tapRecon = [[UITapGestureRecognizer alloc]
                                        initWithTarget:self action:@selector(navigationBarDoubleTap:)];
    tapRecon.numberOfTapsRequired = 1;
    tapRecon.numberOfTouchesRequired = 2;
    [self.navigationBar addGestureRecognizer:tapRecon];
    self.navigationBar.barStyle = [ThemeColors barStyle:[[ThemeManager sharedManager] theme]];
    
    if (self.isDetailView) {
        // Create the root detail view controller
        UIViewController *detailVC = [[UIViewController alloc] init];
        
        // Add button to show master in portrait mode
        detailVC.navigationItem.leftBarButtonItem = self.splitViewController.displayModeButtonItem;
        detailVC.navigationItem.leftItemsSupplementBackButton = YES;
        
        // Set the root view controller of this navigation controller
        [self setViewControllers:@[detailVC] animated:NO];
    }
}


-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    //self.topViewController.title = @"HFR+";
    [self refreshTheme];
}

- (void)navigationController:(UINavigationController *)navigationController willShowViewController:(UIViewController *)viewController animated:(BOOL)animated {
    if ([viewController isKindOfClass:[IASKSpecifierValuesViewController class]]) {
        Theme theme = [[ThemeManager sharedManager] theme];

        [(IASKSpecifierValuesViewController *)viewController setThemeColors:theme];
    }
}
- (NSString *) userThemeDidChange {
    
    NSLog(@"HFR userThemeDidChange");
    
    Theme theme = [[ThemeManager sharedManager] theme];

    
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"theme_noel_disabled"]) {
        [self.navigationBar setBackgroundImage:[ThemeColors imageFromColor:[UIColor clearColor]] forBarMetrics:UIBarMetricsDefault];
    }else{
        UIImage *navBG =[[UIImage animatedImageNamed:@"snow" duration:1.f]
                         resizableImageWithCapInsets:UIEdgeInsetsMake(0, 0, 0, 0) resizingMode:UIImageResizingModeTile];
        
        [self.navigationBar setBackgroundImage:navBG forBarMetrics:UIBarMetricsDefault];
    }
    
    
    [self.navigationBar setBarTintColor:[ThemeColors navBackgroundColor:theme]];
    
    if ([self.navigationBar respondsToSelector:@selector(setTintColor:)]) {
        [self.navigationBar setTintColor:[ThemeColors tintColor:theme]];
    }
    
    [self.navigationBar setTitleTextAttributes:@{NSForegroundColorAttributeName : [ThemeColors titleTextAttributesColor:theme]}];
    
    /*
    if (theme == ThemeLight) {
        [self.navigationBar setBarStyle:UIBarStyleDefault];
    }
    else {
        [self.navigationBar setBarStyle:UIBarStyleBlack];
    }
    */
    
    [self.navigationBar setNeedsDisplay];
    
    [self.topViewController viewWillAppear:NO];

    if ([self.topViewController isKindOfClass:[IASKSpecifierValuesViewController class]]) {
        [(IASKSpecifierValuesViewController *)self.topViewController setThemeColors:theme];
    }
    
    [self refreshTheme];
    
    return @"";
}

- (void)refreshTheme
{
    NSLog(@"refreshTheme");

     UINavigationBarAppearance *app = [UINavigationBarAppearance new];
     if (![[NSUserDefaults standardUserDefaults] boolForKey:@"theme_noel_disabled"]) {
         UIImage *navBG =[[UIImage animatedImageNamed:@"snow" duration:1.f]
                      resizableImageWithCapInsets:UIEdgeInsetsMake(0, 0, 0, 0) resizingMode:UIImageResizingModeTile];
         app.backgroundImage = navBG;
     }
     else {
         [app configureWithOpaqueBackground];
     }
     app.backgroundColor = [ThemeColors navBackgroundColor:[[ThemeManager sharedManager] theme]];
     self.navigationBar.scrollEdgeAppearance = self.navigationBar.standardAppearance = app;
}

-(void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kThemeChangedNotification object:nil];
}

- (void)navigationBarDoubleTap:(UIGestureRecognizer*)recognizer {
    NSLog(@"navigationBarDoubleTapnavigationBarDoubleTap");
    [[ThemeManager sharedManager] switchTheme];
}

- (UIStatusBarStyle)preferredStatusBarStyle{
    return [ThemeColors statusBarStyle:[[ThemeManager sharedManager] theme]];
}


- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    // Return YES for supported orientations
    // Get user preference
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *enabled = [defaults stringForKey:@"landscape_mode"];
    
    if (![enabled isEqualToString:@"none"]) {
        return YES;
    } else {
        return (interfaceOrientation == UIInterfaceOrientationPortrait);
    }
}

/* for iOS6 support */
- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    //NSLog(@"supportedInterfaceOrientations");
    
    if ([[[NSUserDefaults standardUserDefaults] stringForKey:@"landscape_mode"] isEqualToString:@"none"]) {
        return UIInterfaceOrientationMaskPortrait;
    } else {
        return UIInterfaceOrientationMaskAll;
    }
}

- (BOOL)shouldAutorotate
{
    return YES;
}

- (void)traitCollectionDidChange:(UITraitCollection *)previousTraitCollection {
    //NSLog(@"=============== HFRNavigation traitCollectionDidChange 1 ===============");
    [super traitCollectionDidChange:previousTraitCollection];
    if (@available(iOS 13.0, *)) {
        if ([previousTraitCollection hasDifferentColorAppearanceComparedToTraitCollection:self.traitCollection] == false) {
            return;
        }
        //NSLog(@"=============== HFRNavigation traitCollectionDidChange 2 ===============");
        [[ThemeManager sharedManager] checkTheme];
    }
}


@end
