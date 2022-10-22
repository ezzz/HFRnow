//
//  HFRTextView.h
//  HFRplus
//
//  Created by FLK on 13/09/2015.
//
//

#import <UIKit/UIKit.h>

@interface HFRTextView : UITextView <UIAlertViewDelegate>

- (UIMenu *)menuForHFRTextView:(UITextView *)textView editMenuForTextInRange:(NSRange)range suggestedActions:(NSArray<UIMenuElement *> *)suggestedActions;
- (void)insertBBCode:(NSString *)code;

@end
