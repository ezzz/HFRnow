//
//  FavoriteCellView.m
//  SuperHFRplus
//
//  Created by Bruno ARENE on 04/04/2019.
//

#import <Foundation/Foundation.h>
#import "FavoriteCellView.h"
#import "ThemeManager.h"
#import "ThemeColors.h"


@implementation FavoriteCellView


-(void)layoutSubviews {
    [super layoutSubviews];
    [self applyTheme];
}

-(void)applyTheme {
    Theme theme = [[ThemeManager sharedManager] theme];
    [self.labelTitle setTextColor:[ThemeColors textColor:theme]];
    [self.labelMessageNumber setTextColor:[ThemeColors topicMsgTextColor:theme]];
    self.selectionStyle = [ThemeColors cellSelectionStyle:theme];
    if (self.isFavoriteQuoted) {
        [self.imageIsQuoted setHidden:NO];
    }
    else {
        [self.imageIsQuoted setHidden:YES];
    }
    if (self.isSuperFavorite) {
        self.backgroundColor = [ThemeColors cellBackgroundColorSuperFavorite];
        self.contentView.superview.backgroundColor = [ThemeColors cellBackgroundColorSuperFavorite];
        [self.labelDate setTextColor:[ThemeColors tintColorSuperFavorite]];
        [self.labelBadge setTextColor:[ThemeColors cellBackgroundColorSuperFavorite]];
        self.labelBadge.backgroundColor = [ThemeColors tintColorSuperFavorite];
        self.imageIsQuoted.tintColor = [UIColor redColor];//[ThemeColors tintColorSuperFavorite];
    } else {
        self.backgroundColor = [ThemeColors cellBackgroundColor:theme];
        self.contentView.superview.backgroundColor = [ThemeColors cellBackgroundColor:theme];
        [self.labelDate setTextColor:[ThemeColors cellTintColor:theme]];
        [self.labelBadge setTextColor:[ThemeColors cellBackgroundColor:theme]];
        self.labelBadge.backgroundColor = [ThemeColors tintColor];
        self.imageIsQuoted.tintColor = [UIColor redColor];//[ThemeColors tintColor];
    }
    if (self.isFavoriteDisabled) {
        [self.labelTitle setTextColor:[ThemeColors topicMsgTextColor:theme]];
        [self.labelDate setTextColor:[ThemeColors topicMsgTextColor:theme]];
        [self.labelDate setTextColor:[ThemeColors topicMsgTextColor:theme]];
        self.labelBadge.backgroundColor = [ThemeColors topicMsgTextColor:theme];
        [self.imageIsQuoted setHidden:YES];
    }
    if (self.isFavoriteViewed) {
        [self.labelDate setTextColor:[ThemeColors topicMsgTextColor]];
        [self.imageIsQuoted setHidden:YES];
    }
}


@end
