//
//  TopicMPCellView.m
//  SuperHFRplus
//
//  Created by ezzz on 22/10/2022.
//

#import <Foundation/Foundation.h>
#import "TopicMPCellView.h"
#import "Constants.h"
#import "ThemeManager.h"
#import "ThemeColors.h"


@implementation TopicMPCellView

@synthesize titleLabel;
@synthesize msgLabel;
@synthesize timeLabel;
@synthesize imgAvatar;

- (void)awakeFromNib {
    
    [super awakeFromNib];
    
    /*
    if (!SYSTEM_VERSION_GREATER_THAN_OR_EQUAL_TO(@"7.0")) {
        [titleLabel setHighlightedTextColor:[UIColor whiteColor]];
        [msgLabel setHighlightedTextColor:[UIColor whiteColor]];
        [timeLabel setHighlightedTextColor:[UIColor whiteColor]];
    }
    */
}

-(void)layoutSubviews {
    [super layoutSubviews];
    CGRect adjustedFrame = self.accessoryView.frame;
    adjustedFrame.origin.x += 10.0f;
    self.accessoryView.frame = adjustedFrame;
    [self applyTheme];
}

-(void)applyTheme {
    Theme theme = [[ThemeManager sharedManager] theme];
    //self.backgroundColor = [ThemeColors cellBackgroundColor:theme];
    //self.contentView.superview.backgroundColor =[ThemeColors cellBackgroundColor:theme];
    
    self.backgroundColor = self.contentView.superview.backgroundColor = [UIColor clearColor];

    [titleLabel setTextColor:[ThemeColors textColor:theme]];
    [msgLabel setTextColor:[ThemeColors topicMsgTextColor:theme]];
    [timeLabel setTextColor:[ThemeColors cellTintColor:theme]];

    //self.imgAvatar.image = [ThemeColors avatar];
    self.imgAvatar.layer.cornerRadius = self.imgAvatar.frame.size.width / 2;
    self.imgAvatar.clipsToBounds = YES;
    if (self.isPseudoInLoveList) {
        self.imgAvatar.layer.borderWidth = 2.0f;
        self.imgAvatar.layer.borderColor = [ThemeColors loveColor].CGColor;
        NSLog(@"Color love : %@ / %@ ", [ThemeColors loveColor], [ThemeColors loveColor].CGColor);
    }
    else {
        self.imgAvatar.layer.borderWidth = 1.0f;
        self.imgAvatar.layer.borderColor = [ThemeColors textColor2].CGColor;
    }

    self.selectionStyle = [ThemeColors cellSelectionStyle:theme];
    if(topicViewed){
        Theme theme = [[ThemeManager sharedManager] theme];
        [titleLabel setTextColor:[ThemeColors lightTextColor:theme]];
    }
}

-(BOOL)topicViewed{
    return topicViewed;
}

-(void)setTopicViewed:(BOOL)isTopicViewed{
    topicViewed = isTopicViewed;
    [self layoutSubviews];
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];
}


@end
