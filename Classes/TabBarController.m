//
//  TabBarController.m
//  HFRplus
//
//  Created by FLK on 17/09/10.
//

#import "TabBarController.h"
#import "HFRplusAppDelegate.h"
#import "FavoritesTableViewController.h"
#import "HFRMPViewController.h"
#import "ForumsTableViewController.h"
#import "HFRTabBar.h"
#import "ThemeColors.h"
#import "ThemeManager.h"

@implementation TabBarController


-(void)viewDidLoad {
    [super viewDidLoad];
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    { // iPad only
        
        SplitViewController* splitVC0 = [[SplitViewController alloc] initForIndex:0];
        splitVC0.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Catégories" image:[UIImage imageNamed:[ThemeColors tabBarItemUnselectedImageAtIndex:0]] selectedImage:[UIImage imageNamed:[ThemeColors tabBarItemSelectedImageAtIndex:0]]];
        
        SplitViewController* splitVC1 = [[SplitViewController alloc] initForIndex:1];
        splitVC1.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Favoris" image:[UIImage imageNamed:[ThemeColors tabBarItemUnselectedImageAtIndex:1]] selectedImage:[UIImage imageNamed:[ThemeColors tabBarItemSelectedImageAtIndex:1]]];
        
        SplitViewController* splitVC2 = [[SplitViewController alloc] initForIndex:2];
        splitVC2.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Messages" image:[UIImage imageNamed:[ThemeColors tabBarItemUnselectedImageAtIndex:2]] selectedImage:[UIImage imageNamed:[ThemeColors tabBarItemSelectedImageAtIndex:2]]];
        
        SplitViewController* splitVC3 = [[SplitViewController alloc] initForIndex:3];
        splitVC3.tabBarItem = [[UITabBarItem alloc] initWithTitle:@"Plus" image:[UIImage imageNamed:[ThemeColors tabBarItemUnselectedImageAtIndex:3]] selectedImage:[UIImage imageNamed:[ThemeColors tabBarItemSelectedImageAtIndex:3]]];
        
        self.viewControllers = @[splitVC0, splitVC1, splitVC2, splitVC3];
        
        // IOS18 only
        if (@available(iOS 18.0, *)) {
            self.sidebar.hidden = NO;
            self.mode = UITabBarControllerModeAutomatic;
        }
    }
    
    self.title = @"Menu";
    
    for (int i=0; i<self.tabBar.items.count; i++) {
        UITabBarItem *tabBarItem = [self.tabBar.items objectAtIndex:i];
        tabBarItem.selectedImage = [[UIImage imageNamed:[ThemeColors tabBarItemSelectedImageAtIndex:i]]
                                    imageWithRenderingMode:[ThemeColors tabBarItemSelectedImageRendering] ];
        tabBarItem.image = [[UIImage imageNamed:[ThemeColors tabBarItemUnselectedImageAtIndex:i]]
                            imageWithRenderingMode:[ThemeColors tabBarItemUnselectedImageRendering]];
        
        switch (i) {
            case 0: tabBarItem.title = @"Catégories"; break;
            case 1: tabBarItem.title = @"Favoris"; break;
            case 2: tabBarItem.title = @"Messages"; break;
            case 3: tabBarItem.title = @"Plus"; break;
        }
    }
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSString *tab = [defaults stringForKey:@"default_tab"];
    
    if (tab) {
        [self setSelectedIndex:[tab intValue]];
    }
    
    // iPhone only
    // Supprimé pour test:
    // Il y a un triggerpulltorefresh dans ForumsTableViewC. en doublon au démarrage, ce qui génère le popup "Erreur de connection" à chaque démarrage de l'app, car la deuxième requete doit annuler la précédente
    /*
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
    {
        self.tabBar.unselectedItemTintColor = [UIColor colorWithRed:143.0/255.0 green:143.0/255.0 blue:143.0/255.0 alpha:1.0];
        if([((HFRNavigationController *)self.viewControllers[0]).topViewController isKindOfClass:[ForumsTableViewController class]]) {
            //((ForumsTableViewController *)((HFRNavigationController *)self.viewControllers[0]).topViewController).reloadOnAppear = YES;
        }
    }*/
}

-(void)setThemeFromNotification:(NSNotification *)notification{
    [self setTheme:[[ThemeManager sharedManager] theme]];
}

-(void)setTheme:(Theme)theme{
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
    {
        [self.tabBar setTranslucent:NO];

        if(!self.bgView){
            self.bgView = [[UIImageView alloc] initWithImage:[ThemeColors imageFromColor:[UIColor clearColor]]];
            [self.tabBar addSubview:self.bgView];
            [self.tabBar sendSubviewToBack:self.bgView];
            
        }
        
        if(!self.bgOverlayView){
            self.bgOverlayView = [[UIImageView alloc] init];
            [self.tabBar addSubview:self.bgOverlayView];
            [self.tabBar sendSubviewToBack:self.bgOverlayView];
            [self.tabBar sendSubviewToBack:self.bgView];
        }
        
        if(!self.bgOverlayViewBis){
            self.bgOverlayViewBis = [[UIImageView alloc] init];
            [self.tabBar addSubview:self.bgOverlayViewBis];
            [self.tabBar sendSubviewToBack:self.bgOverlayView];
            [self.tabBar sendSubviewToBack:self.bgOverlayViewBis];
            [self.tabBar sendSubviewToBack:self.bgView];
        }
        
        self.bgView.frame = CGRectMake(0, 0, self.tabBar.frame.size.width, self.tabBar.frame.size.height);
        [self.bgView setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight)];
        
        self.bgOverlayView.frame = CGRectMake(0, 0, self.tabBar.frame.size.width, self.tabBar.frame.size.height);
        [self.bgOverlayView setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight)];
        
        self.bgOverlayViewBis.frame = CGRectMake(0, self.tabBar.frame.size.height - 3.f, self.tabBar.frame.size.width, 3.f);
        [self.bgOverlayViewBis setAutoresizingMask:(UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight)];
        
        
        
        if ([[NSUserDefaults standardUserDefaults] boolForKey:@"theme_noel_disabled"]) {
            self.bgOverlayViewBis.image =  [ThemeColors imageFromColor:[UIColor clearColor]];
            self.bgOverlayView.image =  [ThemeColors imageFromColor:[UIColor clearColor]];
        }
        else {
            UIImage *navBG =[[UIImage animatedImageNamed:@"snow" duration:1.f]
                             resizableImageWithCapInsets:UIEdgeInsetsMake(0, 0, 0, 0) resizingMode:UIImageResizingModeTile];
            
            UIImage *tab_snow = [UIImage imageNamed:@"tab_snow"];
            UIImage *tiledImage = [tab_snow resizableImageWithCapInsets:UIEdgeInsetsMake(0, 0, 0, 0) resizingMode:UIImageResizingModeTile];
            self.bgOverlayViewBis.image = tiledImage;
            self.bgOverlayView.image = navBG;
        }
        
        self.bgView.image =[ThemeColors imageFromColor:[ThemeColors tabBackgroundColor:theme]];
        self.tabBar.tintColor = [ThemeColors tintColor];
        
        if ([self.childViewControllers count] > 0) {
            for (int i=0; i<[self.childViewControllers count]; i++) {
                UINavigationController *nvc = (UINavigationController *)[self.childViewControllers objectAtIndex:i];
                nvc.navigationBar.barStyle = [ThemeColors barStyle:theme];
            }
        }
    }
    else {
        if ([self.childViewControllers count] > 0) {
            for (int i=0; i<[self.childViewControllers count]; i++) {
                SplitViewController *splitviewcontroller = (SplitViewController *)[self.viewControllers objectAtIndex:i];
                UINavigationController* nvc = (UINavigationController*)splitviewcontroller.viewControllers.firstObject;
                nvc.navigationBar.barStyle = [ThemeColors barStyle:theme];
            }
        }
    }
    
}


-(void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:kThemeChangedNotification object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(setThemeFromNotification:)
                                            name:kThemeChangedNotification
                                               object:nil];
}


- (void)viewWillTransitionToSize:(CGSize)size withTransitionCoordinator:(id<UIViewControllerTransitionCoordinator>)coordinator {
    [super viewWillTransitionToSize:size withTransitionCoordinator:coordinator];
}

- (void)viewDidLayoutSubviews{
    [super viewDidLayoutSubviews];
    [self setTheme:[[ThemeManager sharedManager] theme]];
}

- (BOOL)tabBarController:(UITabBarController * _Nonnull)tabBarController shouldSelectViewController:(UIViewController * _Nonnull)viewController {

    // iPhone only: actualisation si tap sur l'onglet
    // Sur iPad cela à moins d'intéret car la liste a rafracihir n'est pas directement sous l'onglet mais uniquement sur la vue gauche

    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
    {
        if ([viewController isKindOfClass:[UINavigationController class]]) {
            UINavigationController *nv = (UINavigationController *)viewController;
            
            if ([nv.topViewController isKindOfClass:[ForumsTableViewController class]]) {
                [(ForumsTableViewController *)nv.topViewController reload];
            }
            
            if ([nv.topViewController isKindOfClass:[FavoritesTableViewController class]]) {
                [(FavoritesTableViewController *)nv.topViewController reload];
            }
                        
            if ([nv.topViewController isKindOfClass:[HFRMPViewController class]]) {
                [(HFRMPViewController *)nv.topViewController fetchContent];
            }
            
        }
    }
    return YES;
}

- (void)presentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(void (^)(void))completion {
    
    // Unsure why WKWebView calls this controller - instead of it's own parent controller
    if (self.presentedViewController) {
        NSLog(@"PRESENTED %@", self.presentedViewController);
        [self.presentedViewController presentViewController:viewControllerToPresent animated:flag completion:completion];
    } else {
        [super presentViewController:viewControllerToPresent animated:flag completion:completion];
    }
}



- (void)tabBarController:(UITabBarController *)tabBarController didSelectViewController:(UIViewController *)viewController
{
	NSLog(@"didSelectViewController %@", viewController);
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
    {
        
        if ([viewController isKindOfClass:[UINavigationController class]]) {
            UINavigationController *nv = (UINavigationController *)viewController;
            if ([nv.topViewController isKindOfClass:[FavoritesTableViewController class]]) {
                NSLog("favprotes !!!");
            }
        }
    }
}

// Override to allow orientations other than the default portrait orientation.
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
	
	// Get user preference
	NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
	NSString *enabled = [defaults stringForKey:@"landscape_mode"];
		
	if ([enabled isEqualToString:@"all"]) {
		return YES;
	} else {
		return (interfaceOrientation == UIInterfaceOrientationPortrait);
	}
	
}

// for iOS6 support
- (UIInterfaceOrientationMask)supportedInterfaceOrientations
{
    //NSLog(@"supportedInterfaceOrientations");
    
	if ([[[NSUserDefaults standardUserDefaults] stringForKey:@"landscape_mode"] isEqualToString:@"all"]) {
        //NSLog(@"All");
        
		return UIInterfaceOrientationMaskAll;
	} else {
        //NSLog(@"Portrait");
        
		return UIInterfaceOrientationMaskPortrait;
	}
}


- (BOOL)shouldAutorotate
{
    //NSLog(@"shouldAutorotate");

    return YES;
}
    
@end
