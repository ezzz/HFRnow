//
//  SettingsViewController.h
//  HFRplus
//
//  Created by FLK on 05/07/12.
//

#import <UIKit/UIKit.h>

#if APP_SWIFT

@interface PlusSettingsViewController : UIViewController <UIAlertViewDelegate, UITableViewDelegate> {
}

@property (nonatomic, strong) UIActivityIndicatorView *spinner;

@end

#else

@import InAppSettingsKit;

@interface PlusSettingsViewController : IASKAppSettingsViewController <IASKSettingsDelegate, UIAlertViewDelegate, UITableViewDelegate> {

}

@property (nonatomic, strong) UIActivityIndicatorView *spinner;

@end

#endif
