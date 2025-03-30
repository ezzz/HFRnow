//
//  HFRplusAppDelegate.h
//  HFRplus
//
//  Created by FLK on 18/08/10.
//

#import <UIKit/UIKit.h>
#import "Constants.h"
#import "TabBarController.h"
#import "SplitViewController.h"
#import <BackgroundTasks/BackgroundTasks.h>

@import InAppSettingsKit;

#import "Reachability.h"
#import <UserNotifications/UserNotifications.h>

@interface HFRplusAppDelegate : NSObject<UNUserNotificationCenterDelegate> {
    UIWindow *window;
    TabBarController *rootController;    
    SplitViewController *splitViewController;

    UINavigationController *forumsNavController;
    UINavigationController *favoritesNavController;
    UINavigationController *messagesNavController;
    UINavigationController *searchNavController;
    
    BOOL isLoggedIn;
    BOOL statusChanged;    
    
   // NSOperationQueue *ioQueue;
    NSTimer *periodicMaintenanceTimer;
    //NSOperation *periodicMaintenanceOperation;
    
    NSString *hash_check;
    
    Reachability* internetReach;

}

- (void)periodicMaintenance;

@property (nonatomic, strong) IBOutlet UIWindow *window;
//@property (nonatomic, strong) IBOutlet TabBarController *rootController;
@property (strong, nonatomic) IBOutlet TabBarController *rootController;

@property (nonatomic, strong) IBOutlet SplitViewController *splitViewController;

//@property (nonatomic, strong) IBOutlet UINavigationController *forumsNavController;
@property (strong, nonatomic) IBOutlet UIViewController *forumsNavController;

@property (nonatomic, strong) IBOutlet UINavigationController *favoritesNavController;
@property (nonatomic, strong) IBOutlet UINavigationController *messagesNavController;
@property (nonatomic, strong) IBOutlet UINavigationController *plusNavController;
@property (nonatomic, strong) IBOutlet UINavigationController *searchNavController;

@property BOOL isLoggedIn;
@property BOOL statusChanged;

@property (nonatomic, strong) NSString *hash_check;

@property (nonatomic, strong) Reachability *internetReach;

+ (HFRplusAppDelegate *)sharedAppDelegate;
- (BOOL)legacy_application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions;
- (void)hidePrimaryPanelOnIpadForSplitViewController:(UISplitViewController*) splitViewController;
- (void)updateMPBadgeWithString:(NSString *)badgeValue;
- (void)updatePlusBadgeWithString:(NSString *)badgeValue;
- (void)readMPBadge;
- (void)openURL:(NSString *)stringUrl;

- (void)login;
- (void)checkLogin;
- (void)logout;

- (void)resetApp;
- (void)checkForNewMP:(BGAppRefreshTask *)task;
- (void)registerDefaultsFromSettingsBundle;
@end

