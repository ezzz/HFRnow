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
    self.backgroundColor = self.contentView.superview.backgroundColor = [ThemeColors cellBackgroundColor:theme];

    [msgLabel setTextColor:[ThemeColors topicMsgTextColor:theme]];
    if (self.topicViewed) {
        [timeLabel setTextColor:[ThemeColors topicMsgTextColor:theme]];
    }
    else {
        [timeLabel setTextColor:[ThemeColors cellTintColor:theme]];
    }
    self.imgAvatar.layer.cornerRadius = self.imgAvatar.frame.size.width / 2;
    self.imgAvatar.clipsToBounds = YES;
    
    if (self.isPseudoInLoveList) {
        self.imgAvatar.layer.borderWidth = 2.0f;
        self.imgAvatar.layer.borderColor = [ThemeColors loveColorBright].CGColor;
        self.contentView.superview.backgroundColor = [ThemeColors loveColor];
    }
    else {
        self.imgAvatar.layer.borderWidth = 1.0f;
        self.imgAvatar.layer.borderColor = [ThemeColors textColor2].CGColor;
    }

    self.selectionStyle = [ThemeColors cellSelectionStyle:theme];
    
    [titleLabel setTextColor:[ThemeColors textColor:theme]];
    if (topicViewed){
        Theme theme = [[ThemeManager sharedManager] theme];
        [titleLabel setTextColor:[ThemeColors lightTextColor:theme]];
    }
    
    if (self.isTopicViewedByReceiver == NO && self.titleLabel.text.length >= 8) {
        NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithAttributedString: self.titleLabel.attributedText];
        [text addAttribute:NSForegroundColorAttributeName value:[UIColor redColor] range:NSMakeRange(0, 8)];
        [self.titleLabel setAttributedText: text];
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
