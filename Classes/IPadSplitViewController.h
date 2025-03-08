//
//  IPadSplitViewController.h
//  HFRnow
//
//  Created by Bruno ARENE on 08/03/2025.
//


#import <UIKit/UIKit.h>

#import "CustomTabBarController.h"
#import "DetailNavigationViewController.h"


@interface IPadSplitViewController : UISplitViewController

@property (nonatomic, strong) CustomTabBarController *leftVC;
@property (nonatomic, strong) DetailNavigationViewController *rightVC;

@end
