//
//  HFRplusTabBar.m
//  SuperHFRplus
//
//  Created by Aynolor on 18.10.21.
//

#import "HFRplusTabBar.h"

@implementation HFRplusTabBar

// In iOS 11, UITabBarItem's have the title to the right of the icon in horizontally regular environments
// (i.e. the iPad).  In order to keep the title below the icon, it was necessary to subclass UITabBar and override
// traitCollection to make it horizontally compact.

- (UITraitCollection *)traitCollection {
    return [UITraitCollection traitCollectionWithHorizontalSizeClass:UIUserInterfaceSizeClassCompact];
}

@end
