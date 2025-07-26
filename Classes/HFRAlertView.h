//
//  HFRAlertView.h
//  SuperHFRplus
//
//  Created by Bruno ARENE on 06/03/2019.
//

#import <UIKit/UIKit.h>

#ifndef HFRAlertView_h
#define HFRAlertView_h

@interface HFRAlertView : NSObject {
}

+ (void) DisplayAlertViewWithTitle:(NSString*)sTitle forDuration:(long)lDuration;
+ (void) DisplayAlertViewWithTitle:(NSString*)sTitle andMessage:(NSString*)sMessage forDuration:(long)lDuration;
+ (void) DisplayAlertViewWithTitle:(NSString*)sTitle andMessage:(NSString*)sMessage forDuration:(long)lDuration completion:(void (^)(void))completion;
+ (void) DisplayAlertViewWithTitle:(NSString*)sTitle andMessage:(NSString*)sMessage forDuration:(long)lDuration completion:(void (^)(void))completion baseController:(UIViewController*)vc;

+ (void) DisplayOKAlertViewWithTitle:(NSString*)sTitle andMessage:(NSString*)sMessage;
+ (void) DisplayOKAlertViewWithTitle:(NSString*)sTitle andMessage:(NSString*)sMessage handlerOK:(void (^ __nullable)(UIAlertAction *action))handlerOK baseController:(UIViewController*)vc;
+ (void) DisplayOKAlertViewWithTitle:(NSString*)sTitle andMessage:(NSString*)sMessage handlerOK:(void (^ __nullable)(UIAlertAction *action))handlerOK;
+ (void) DisplayOKAlertViewWithTitle:(NSString*)sTitle andMessage:(NSString*)sMessage completion:(void (^)(void))completion;
+ (void) DisplayOKCancelAlertViewWithTitle:(NSString*)sTitle andMessage:(NSString*)sMessage handlerOK:(void (^ __nullable)(UIAlertAction *action))handlerOK;
+ (void) DisplayOKCancelAlertViewWithTitle:(NSString*)sTitle andMessage:(NSString*)sMessage handlerOK:(void (^ __nullable)(UIAlertAction *action))handlerOK handlerCancel:(void (^ __nullable)(UIAlertAction *action))handlerCancel;
+ (void) DisplayOKCancelAlertViewWithTitle:(NSString*)sTitle andMessage:(NSString*)sMessage handlerOK:(void (^ __nullable)(UIAlertAction *action))handlerOK handlerCancel:(void (^ __nullable)(UIAlertAction *action))handlerCancel baseController:(UIViewController*)vc;

@end

#endif /* HFRAlertView_h */
