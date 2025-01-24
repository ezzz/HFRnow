//
//  TopicMPCellView.h
//  SuperHFRplus
//
//  Created by ezzz on 22/10/2022.
//

#ifndef TopicMPCellView_h
#define TopicMPCellView_h

#import <UIKit/UIKit.h>


@interface TopicMPCellView : UITableViewCell {
    IBOutlet UILabel *titleLabel;
    IBOutlet UILabel *msgLabel;
    IBOutlet UILabel *timeLabel;
    BOOL topicViewed;
}

@property (nonatomic, strong) IBOutlet UILabel *titleLabel;
@property (nonatomic, strong) IBOutlet UILabel *msgLabel;
@property (nonatomic, strong) IBOutlet UILabel *timeLabel;
@property (strong, nonatomic) IBOutlet UIImageView *imgAvatar;
@property BOOL topicViewed;
@property BOOL isTopicClosed;
@property BOOL isTopicViewedByReceiver;
@property BOOL isPseudoInLoveList;

@end

#endif /* TopicMPCellView_h */
