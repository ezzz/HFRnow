//
//  PopupViewController.h
//  SuperHFRplus
//
//  Created by ezzz on 07/11/2021.
//

#ifndef PopupViewController_h
#define PopupViewController_h

@interface PopupViewController : UIViewController {
}
@property (weak, nonatomic) IBOutlet UILabel *message;
@property (weak, nonatomic) IBOutlet UIButton *btnAction;
@property dispatch_block_t handlerAction;
- (void)configurePopupWithLabel:(NSString*)sLabel buttonName:(NSString*)sButtonText action:(dispatch_block_t)blockHandlerAction;

@end

#endif /* PopupViewController_h */
