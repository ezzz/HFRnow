//
//  SmileyAlertView.h
//  HFRplus
//
//  Created by ezzz on 19/09/2021.
//

#import <Foundation/Foundation.h>

@class SmileyCodeTableViewController;

@interface SmileyAlertView : NSObject
{
}

@property NSString* sSelectedSmileyCode;
@property NSString* sSelectedSmileyImageURL;
@property UIAlertAction* actionSmileyCode;
@property BOOL bAddSmiley;
@property BOOL bShowKeywords;
@property SmileyCodeTableViewController* smileyCodeTableViewController;
+ (SmileyAlertView *)shared;

- (void) displaySmileyAjouterCancel:(NSString *)sSmileyCode withUrl:(NSString *)sSmileyImgUrl showKeyworkds:(BOOL)bShowKeywords baseController:(UIViewController*)vc;
- (void) displaySmileyRetirerCancel:(NSString *)sSmileyCode withUrl:(NSString *)sSmileyImgUrl showKeyworkds:(BOOL)bShowKeywords baseController:(UIViewController*)vc;

/*
 - (void) displaySmileyActionCancel:(NSString *)sSmileyCode withUrl:(NSString *)sSmileyImgUrl handlerOK:(void (^ __nullable)(UIAlertAction *action))handlerOK handlerCancel:(void (^ __nullable)(UIAlertAction *action))handlerCancel baseController:(UIViewController*)vc;

*/
@end
