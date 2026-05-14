//
//  ThemeManager.m
//  HFRplus
//
//  Created by Aynolor on 17/02/17.
//
//

#import "ThemeManager.h"
#import "ThemeColors.h"
#import "HFRswift-Swift.h"
#import "AvatarTableViewCell.h"
#if !APP_SWIFT
#import "PlusCellView.h"
#import "SimpleCellView.h"
#endif
#include <stdlib.h>

static NSString * const HFRAutoThemeKey = @"auto_theme";
static NSString * const HFRManualThemeKey = @"theme";

@interface ThemeManager ()
- (Theme)boundedTheme:(Theme)candidate;
- (UITraitCollection *)currentTraitCollection;
- (Theme)resolvedThemeForTraitCollection:(UITraitCollection *)traitCollection;
- (void)synchronizeResolvedTheme;
- (void)postThemeChangedNotification;
- (BOOL)normalizeAutoThemeSettingIfNeeded;
- (BOOL)removeDeprecatedThemeKeysIfNeeded;
@end

@implementation ThemeManager

@synthesize theme = _theme;

#pragma mark Singleton Methods

+ (ThemeManager*)sharedManager {
    static ThemeManager *sharedThemeManager = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        sharedThemeManager = [[self alloc] init];
    });
    return sharedThemeManager;
}

+ (Theme) currentTheme {
    return [[ThemeManager sharedManager] theme];
}

- (id)init {
    if (self = [super init]) {
        BOOL didNormalize = [self normalizeAutoThemeSettingIfNeeded];
        BOOL didCleanup = [self removeDeprecatedThemeKeysIfNeeded];
        [self synchronizeResolvedTheme];
        if (didNormalize || didCleanup) {
            [[NSUserDefaults standardUserDefaults] synchronize];
        }
        [self applyAppearance];
    }
    return self;
}

- (Theme)theme {
    [self synchronizeResolvedTheme];
    return _theme;
}

- (void)setTheme:(Theme)newTheme {
    _theme = [self boundedTheme:newTheme];
}

- (BOOL)isLightForTraitCollection:(UITraitCollection *)traitCollection {
    if ([[NSUserDefaults standardUserDefaults] integerForKey:HFRAutoThemeKey] == AUTO_THEME_AUTO_IOS) {
        return [self resolvedThemeForTraitCollection:traitCollection] == ThemeLight;
    }
    return self.theme == ThemeLight;
}

- (void)switchTheme {
    Theme currentTheme = self.theme;
    [self setThemeManually:(currentTheme == ThemeLight) ? ThemeDark : ThemeLight];
}

- (void)refreshTheme {
    BOOL didNormalize = [self normalizeAutoThemeSettingIfNeeded];
    BOOL didCleanup = [self removeDeprecatedThemeKeysIfNeeded];
    [self synchronizeResolvedTheme];
    if (didNormalize || didCleanup) {
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    [self postThemeChangedNotification];
    [self applyAppearance];
}

- (void)checkTheme {
    BOOL didNormalize = [self normalizeAutoThemeSettingIfNeeded];
    BOOL didCleanup = [self removeDeprecatedThemeKeysIfNeeded];
    Theme previousTheme = _theme;
    Theme resolvedTheme = [self resolvedThemeForTraitCollection:nil];

    if (!didNormalize && !didCleanup && previousTheme == resolvedTheme) {
        return;
    }

    _theme = resolvedTheme;
    if (didNormalize || didCleanup) {
        [[NSUserDefaults standardUserDefaults] synchronize];
    }
    [self postThemeChangedNotification];
    [self applyAppearance];
}

-(void)applyAppearance {
    Theme resolvedTheme = self.theme;

    if ([[UITextField appearance] respondsToSelector:@selector(setKeyboardAppearance:)]) {
        [UITextField appearance].keyboardAppearance = [ThemeColors keyboardAppearance:resolvedTheme];
    }

    [[UIView appearanceWhenContainedInInstancesOfClasses:@[[UIAlertController class]]]
     setTintColor:[ThemeUserColorStore actionTintColorForLegacyThemeValue:resolvedTheme]];
}

- (void)applyThemeToCell:(UITableViewCell *)cell{
    Theme resolvedTheme = self.theme;

    cell.backgroundColor = [ThemeColors cellBackgroundColor:resolvedTheme];
    cell.textLabel.textColor = [ThemeColors cellTextColor:resolvedTheme];
    if ([cell respondsToSelector:@selector(setTintColor:)]) {
        cell.tintColor = [ThemeUserColorStore actionTintColorForLegacyThemeValue:resolvedTheme];
    }

    if(![cell isKindOfClass:[AvatarTableViewCell class]]){
        if ([cell.imageView respondsToSelector:@selector(setTintColor:)]) {
            UIImage *img =[cell.imageView.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
            cell.imageView.image = img;
            cell.imageView.tintColor = [ThemeColors cellIconColor:resolvedTheme];
        }
    }

#if !APP_SWIFT
    if([cell isKindOfClass:[PlusCellView class]]){
        PlusCellView* plusCellView = (PlusCellView*)cell;
        UIImage *img =[plusCellView.titleImage.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        plusCellView.titleImage.image = img;
        plusCellView.titleImage.tintColor = [ThemeColors cellIconColor:resolvedTheme];
    }
#endif

#if !APP_SWIFT
    if([cell isKindOfClass:[SimpleCellView class]]){
        SimpleCellView* simpleCellView = (SimpleCellView*)cell;
        UIImage *img = [simpleCellView.imageIcon.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
        simpleCellView.imageIcon.image = img;
        simpleCellView.imageIcon.tintColor = [ThemeColors cellIconColor:resolvedTheme];
    }
#endif

    cell.selectionStyle = [ThemeColors cellSelectionStyle:resolvedTheme];
}

- (void)applyThemeToTextField:(UITextField *)textfield{
    Theme resolvedTheme = self.theme;

    textfield.backgroundColor = [ThemeColors textFieldBackgroundColor:resolvedTheme];
    textfield.textColor = [ThemeColors cellTextColor:resolvedTheme];
    if ([textfield respondsToSelector:@selector(setTintColor:)]) {
        textfield.tintColor = [ThemeColors cellTextColor:resolvedTheme];
    }

    UIButton *btnClear = [textfield valueForKey:@"_clearButton"];
    UIImage *imageNormal = [btnClear imageForState:UIControlStateNormal];
    UIGraphicsBeginImageContextWithOptions(imageNormal.size, NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();

    CGRect rect = (CGRect){ CGPointZero, imageNormal.size };
    CGContextSetBlendMode(context, kCGBlendModeNormal);
    [imageNormal drawInRect:rect];

    CGContextSetBlendMode(context, kCGBlendModeSourceIn);
    [[UIColor whiteColor] setFill];
    CGContextFillRect(context, rect);

    UIImage *imageTinted  = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    [btnClear setImage:imageTinted forState:UIControlStateNormal];

    textfield.attributedPlaceholder = [[NSAttributedString alloc] initWithString:textfield.attributedPlaceholder.string
        attributes:@{
            NSForegroundColorAttributeName: [ThemeColors placeholderColor:resolvedTheme]
        }
    ];
}

- (void)applyThemeToAlertController:(UIAlertController *)alert{
    Theme resolvedTheme = self.theme;

    UIView *firstSubview = alert.view.subviews.firstObject;
    UIView *alertContentView = firstSubview.subviews.firstObject;
    for (UIView *subSubView in alertContentView.subviews) {
        subSubView.backgroundColor = [ThemeColors alertBackgroundColor:resolvedTheme];
    }

    [alertContentView.subviews objectAtIndex:1].alpha = 0.0f;

    if (alert.title != nil)
    {
        NSAttributedString* attributedString = [[NSAttributedString alloc] initWithString:alert.title attributes:@{NSForegroundColorAttributeName: [ThemeColors textColor:resolvedTheme], NSFontAttributeName: [UIFont systemFontOfSize:17.f weight:UIFontWeightSemibold]}];
        [alert setValue:attributedString forKey:@"attributedTitle"];
    }
    if (alert.message != nil)
    {
        NSAttributedString* attributedString2 = [[NSAttributedString alloc] initWithString:alert.message attributes:@{NSForegroundColorAttributeName: [ThemeColors textColor:resolvedTheme], NSFontAttributeName: [UIFont systemFontOfSize:13.f weight:UIFontWeightRegular]}];
        [alert setValue:attributedString2 forKey:@"attributedMessage"];
    }

    if (![[NSUserDefaults standardUserDefaults] boolForKey:@"theme_noel_disabled"]) {
        if (alert.preferredStyle != UIAlertControllerStyleActionSheet && alert.title && (alert.actions.count == 0
                                                                                         || [alert.title containsString:@"Err"] || [alert.title containsString:@"Oo"] )) {
            int iImageSize = 25;
            [alert setTitle:[NSString stringWithFormat:@"\n%@",alert.title]];
            NSString* is1 = [NSString stringWithFormat:@"noel%02d", (int)arc4random_uniform(23)];
            if ([alert.title containsString:@"Oo"] || [alert.title containsString:@"Err"]) {
                is1 = @"noel_dinde";
                iImageSize = 30;
            }
            else if ([alert.title containsString:@"Noël"]) {
                is1 = @"noel05";
            }
            UIImage *i1 = [UIImage imageNamed:is1];
            UIImageView* iv1 = [[UIImageView alloc] initWithFrame:CGRectMake(10, 10, iImageSize, iImageSize)];
            [iv1 setImage:i1];
            [alert.view addSubview:iv1];

            iv1.translatesAutoresizingMaskIntoConstraints = NO;
            NSLayoutConstraint *centerHorizontal = [NSLayoutConstraint constraintWithItem:iv1 attribute:NSLayoutAttributeCenterX relatedBy:NSLayoutRelationEqual toItem:alert.view attribute:NSLayoutAttributeCenterX multiplier:1.0f constant:0.0f];
            NSLayoutConstraint *top = [NSLayoutConstraint constraintWithItem:iv1 attribute:NSLayoutAttributeTop relatedBy:NSLayoutRelationEqual toItem:alert.view attribute:NSLayoutAttributeTop multiplier:1 constant:10];
            NSLayoutConstraint *height = [NSLayoutConstraint constraintWithItem:iv1 attribute:NSLayoutAttributeHeight relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:iImageSize];
            NSLayoutConstraint *width = [NSLayoutConstraint constraintWithItem:iv1 attribute:NSLayoutAttributeWidth relatedBy:NSLayoutRelationEqual toItem:nil attribute:NSLayoutAttributeNotAnAttribute multiplier:1 constant:iImageSize];
            [alert.view addConstraints:@[centerHorizontal, top, height, width]];
        }

        UIImage* originalImage;
        if (resolvedTheme == ThemeLight) {
            originalImage = [UIImage imageNamed:@"noel_neige_big_red"];
        }
        else {
            originalImage = [UIImage imageNamed:@"noel_neige_big"];
        }
        CGFloat scale = 1.5;
        if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad) {
            scale = 2.0;
        }
        UIImage *scaledImage = [UIImage imageWithCGImage:[originalImage CGImage] scale:(originalImage.scale * scale) orientation:(originalImage.imageOrientation)];
        UIImageView *snowBackground = [[UIImageView alloc] initWithImage:scaledImage];
        snowBackground.frame = CGRectMake(0, 0, 200, 200);
        snowBackground.contentMode = UIViewContentModeTopLeft;
        [alert.view addSubview:snowBackground];
        [alert.view sendSubviewToBack:snowBackground];
        alert.view.clipsToBounds = YES;
        alert.view.layer.cornerRadius = 20;
        alert.view.layer.masksToBounds = YES;
    }
}

- (void)setThemeManually:(Theme)newTheme {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:AUTO_THEME_MANUAL forKey:HFRAutoThemeKey];
    [defaults setInteger:[self boundedTheme:newTheme] forKey:HFRManualThemeKey];
    [defaults removeObjectForKey:@"force_manual_theme"];
    [self refreshTheme];
}

- (Theme)boundedTheme:(Theme)candidate {
    return candidate == ThemeDark ? ThemeDark : ThemeLight;
}

- (UITraitCollection *)currentTraitCollection {
    if (@available(iOS 13.0, *)) {
        NSSet<UIScene *> *scenes = [UIApplication sharedApplication].connectedScenes;
        for (UIScene *scene in scenes) {
            if (![scene isKindOfClass:[UIWindowScene class]]) {
                continue;
            }
            UIWindowScene *windowScene = (UIWindowScene *)scene;
            for (UIWindow *window in windowScene.windows) {
                if (window.isKeyWindow) {
                    return window.traitCollection;
                }
            }
        }
    }
    return [UIScreen mainScreen].traitCollection;
}

- (Theme)resolvedThemeForTraitCollection:(UITraitCollection *)traitCollection {
    NSInteger autoTheme = [[NSUserDefaults standardUserDefaults] integerForKey:HFRAutoThemeKey];
    if (autoTheme == AUTO_THEME_AUTO_IOS) {
        UITraitCollection *resolvedTraitCollection = traitCollection ?: [self currentTraitCollection];
        return resolvedTraitCollection.userInterfaceStyle == UIUserInterfaceStyleDark ? ThemeDark : ThemeLight;
    }
    NSInteger manualTheme = [[NSUserDefaults standardUserDefaults] integerForKey:HFRManualThemeKey];
    return [self boundedTheme:(Theme)manualTheme];
}

- (void)synchronizeResolvedTheme {
    _theme = [self resolvedThemeForTraitCollection:nil];
}

- (void)postThemeChangedNotification {
    NSNotification *myNotification = [NSNotification notificationWithName:kThemeChangedNotification
                                                                  object:self
                                                                userInfo:nil];
    [[NSNotificationCenter defaultCenter] postNotification:myNotification];
}

- (BOOL)normalizeAutoThemeSettingIfNeeded {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSInteger autoTheme = [defaults integerForKey:HFRAutoThemeKey];
    if (autoTheme == AUTO_THEME_MANUAL || autoTheme == AUTO_THEME_AUTO_IOS) {
        return NO;
    }
    [defaults setInteger:AUTO_THEME_AUTO_IOS forKey:HFRAutoThemeKey];
    return YES;
}

- (BOOL)removeDeprecatedThemeKeysIfNeeded {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSArray<NSString *> *deprecatedKeys = @[@"force_manual_theme", @"auto_theme_day_time", @"auto_theme_night_time"];
    BOOL didRemoveKey = NO;

    for (NSString *key in deprecatedKeys) {
        if ([defaults objectForKey:key] == nil) {
            continue;
        }
        [defaults removeObjectForKey:key];
        didRemoveKey = YES;
    }

    return didRemoveKey;
}

@end
