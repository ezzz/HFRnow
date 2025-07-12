//
//  ThemeManager.h
//  HFRplus
//
//  Created by Aynolor on 17/02/17.
//
//

#import <Foundation/Foundation.h>
#import "Constants.h"
#import "LuminosityHandler.h"

#define AUTO_THEME_MANUAL 0
#define AUTO_THEME_AUTO_CAMERA 1
#define AUTO_THEME_AUTO_TIME 2 // No more used but kept for compatibility
#define AUTO_THEME_AUTO_IOS 3 // No more used but kept for compatibility

#define MANUAL_THEME_LIGHT 0
#define MANUAL_THEME_DARK 1

@interface ThemeManager : NSObject <LuminosityHandlerDelegate>  {
}

@property Theme theme;
@property LuminosityHandler *luminosityHandler;

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
- (Theme)getThemeFromCurrentTime;

@end
