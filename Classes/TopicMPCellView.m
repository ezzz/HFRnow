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
    self.selectionStyle = [ThemeColors cellSelectionStyle:theme];

    [msgLabel setTextColor:[ThemeColors topicMsgTextColor:theme]];
    
    if (self.topicViewed) {
        [timeLabel setTextColor:[ThemeColors topicMsgTextColor:theme]];
    }
    else {
        [timeLabel setTextColor:[ThemeColors cellTintColor:theme]];
    }
    
    //NSLog(@"Is %@ in love list %@", msgLabel.text, self.isPseudoInLoveList ? @"Yes" : @"No");
    if (self.isPseudoInLoveList) {
        self.imgAvatar.layer.borderWidth = 2.0f;
        self.imgAvatar.layer.borderColor = [ThemeColors loveColorBright].CGColor;
    }
    else {
        self.imgAvatar.layer.borderWidth = 1.0f;
        self.imgAvatar.layer.borderColor = [ThemeColors textColor2].CGColor;
    }
    
    [titleLabel setTextColor:[ThemeColors textColor:theme]];
    if (topicViewed){
        Theme theme = [[ThemeManager sharedManager] theme];
        [titleLabel setTextColor:[ThemeColors lightTextColor:theme]];
    }
    
    if (self.isTopicViewedByReceiver == NO) {
        NSMutableAttributedString *text = [[NSMutableAttributedString alloc] initWithAttributedString: self.titleLabel.attributedText];
        if (self.isTopicClosed && self.titleLabel.text.length >= 10) {
            [text addAttribute:NSForegroundColorAttributeName value:[UIColor redColor] range:NSMakeRange(2, 8)];
        }
        else if (self.titleLabel.text.length >= 8) {
            [text addAttribute:NSForegroundColorAttributeName value:[UIColor redColor] range:NSMakeRange(0, 8)];
        }
        [self.titleLabel setAttributedText: text];
    }
}

-(BOOL)topicViewed{
    return topicViewed;
}

-(void)setTopicViewed:(BOOL)isTopicViewed{
    topicViewed = isTopicViewed;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {
    [super setSelected:selected animated:animated];
}


@end
