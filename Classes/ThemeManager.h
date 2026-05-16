//
//  ThemeManager.h
//  HFRplus
//
//  Created by Aynolor on 17/02/17.
//
//

#import <Foundation/Foundation.h>
#import "Constants.h"

#define AUTO_THEME_MANUAL 0
#define AUTO_THEME_AUTO_IOS 3

#define MANUAL_THEME_LIGHT 0
#define MANUAL_THEME_DARK 1

@interface ThemeManager : NSObject {
}

@property Theme theme;

+ (ThemeManager*)sharedManager;
+ (Theme)currentTheme;

- (BOOL)isLightForTraitCollection:(UITraitCollection *)traitCollection;
- (void)applyThemeToCell:(UITableViewCell *)cell;
- (void)applyThemeToTextField:(UITextField *)textfield;
- (void)applyThemeToAlertController:(UIAlertController *)alert;
- (void)switchTheme;
- (void)refreshTheme;
- (void)checkTheme;
- (void)setThemeManually:(Theme)newTheme;

@end
