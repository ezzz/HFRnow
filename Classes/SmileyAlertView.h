//
//  SmileyAlertView.h
//  HFRplus
//
//  Created by ezzz on 19/09/2021.
//

#import <Foundation/Foundation.h>

@class SmileyCodeTableViewController;

typedef void (^nsstring_block_t)(NSString*);

@interface SmileyAlertView : NSObject
{
}

@property NSString* sSelectedSmileyCode;
@property NSString* sSelectedSmileyImageURL;
@property nsstring_block_t handlerSelectCode;
@property dispatch_block_t handlerDone;
@property dispatch_block_t handlerFailed;
@property UIAlertAction* actionSmileyCode;
@property BOOL bAddSmiley;
@property SmileyCodeTableViewController* smileyCodeTableViewController;
+ (SmileyAlertView *)shared;

- (void) displaySmileyActionCancel:(NSString *)sSmileyCode withUrl:(NSString *)sSmileyImgUrl addSmiley:(BOOL)bAddSmiley showAction:(BOOL)bShowAction handlerDone:(dispatch_block_t)handlerDone handlerFailed:(dispatch_block_t)handlerFailed handlerSelectCode:(nsstring_block_t)handlerSelectCode baseController:(UIViewController*)vc;
@end
