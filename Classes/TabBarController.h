//
//  TabBarController.h
//  HFRplus
//
//  Created by FLK on 17/09/10.
//

#import <UIKit/UIKit.h>
#import "BrowserViewController.h"
#import "Constants.h"
#import "ForumsTableViewController.h"
#import "FavoritesTableViewController.h"

@interface TabBarController : UITabBarController <UITabBarControllerDelegate> {

}

@property (nonatomic, strong) UIImageView *bgView;
@property (nonatomic, strong) UIImageView *bgOverlayView;
@property (nonatomic, strong) UIImageView *bgOverlayViewBis;
@property (weak, nonatomic) IBOutlet UIView *viewFavorites;
@property (weak, nonatomic) IBOutlet UIView *viewForums;
@property (nonatomic, strong) ForumsTableViewController* forumsTableViewController;
@property (nonatomic, strong) FavoritesTableViewController* favoritesTableViewController;

-(void)popAllToRoot:(BOOL)includingSelectedIndex;
@end
