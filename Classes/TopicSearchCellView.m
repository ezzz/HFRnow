//
//  TopicCellView.m
//  HFRplus
//
//  Created by FLK on 23/09/10.
//

#import "TopicSearchCellView.h"
#import "Constants.h"
#import "ThemeManager.h"
#import "ThemeColors.h"


@implementation TopicSearchCellView

@synthesize titleLabel, contentLabel, msgLabel, timeLabel;

- (id)initWithStyle:(UITableViewCellStyle)style reuseIdentifier:(NSString *)reuseIdentifier {
    if ((self = [super initWithStyle:style reuseIdentifier:reuseIdentifier])) {
        // Initialization code
    }
    return self;
}

- (void)setSelected:(BOOL)selected animated:(BOOL)animated {

    [super setSelected:selected animated:animated];

    // Configure the view for the selected state
}

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
    self.backgroundColor = [ThemeColors cellBackgroundColor:theme];
    self.contentView.superview.backgroundColor =[ThemeColors cellBackgroundColor:theme];
    [titleLabel setTextColor:[ThemeColors textColor:theme]];
    [contentLabel setTextColor:[ThemeColors textColor:theme]];
    [msgLabel setTextColor:[ThemeColors topicMsgTextColor:theme]];
    [timeLabel setTextColor:[ThemeColors cellTintColor:theme]];

    //self.imgGroup.image = [self.imgGroup.image imageWithRenderingMode:UIImageRenderingModeAlwaysTemplate];
    //self.imgGroup.tintColor = [ThemeColors topicMsgTextColor:theme];

    self.selectionStyle = [ThemeColors cellSelectionStyle:theme];
    if (self.topicViewed) {
        Theme theme = [[ThemeManager sharedManager] theme];
        [titleLabel setTextColor:[ThemeColors lightTextColor:theme]];
        [timeLabel setTextColor:[ThemeColors lightTextColor:theme]];
    }
    
    //self.selectedBackgroundView.backgroundColor = [UIColor redColor];
}

@end
