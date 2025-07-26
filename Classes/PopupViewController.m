//
//  PopupViewController.m
//  SuperHFRplus
//
//  Created by ezzz on 07/11/2021.
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import "PopupViewController.h"
#import "ThemeColors.h"
#import "ThemeManager.h"

@implementation PopupViewController;

- (id)init {
    self = [super init];
    if (self) {
    }
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    //UINib *nib = [UINib nibWithNibName:@"PopupViewController" bundle:nil];
    self.view.layer.cornerRadius = 10;
    self.view.layer.masksToBounds = true;
    [self.btnAction setHidden:YES];
}

- (void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    self.view.backgroundColor = [ThemeColors toolbarColor:[ThemeManager currentTheme]];
    
    
    CALayer *layer = self.view.layer;
    layer.cornerRadius = self.view.frame.size.height/4;
    layer.masksToBounds = NO;

    layer.shadowOffset = CGSizeMake(2, 5);
    layer.shadowColor = [[UIColor blackColor] CGColor];
    layer.shadowRadius = 10.0f;
    layer.shadowOpacity = 0.4f;
    layer.shadowPath = [[UIBezierPath bezierPathWithRoundedRect:layer.bounds cornerRadius:layer.cornerRadius] CGPath];

    CGColorRef bColor = self.view.backgroundColor.CGColor;
    self.view.backgroundColor = nil;
    layer.backgroundColor = bColor;
    //[self.viewCancelActionSmiley setHidden:YES];
}

- (void)configurePopupWithLabel:(NSString*)sLabel buttonName:(NSString*)sButtonText action:(dispatch_block_t)blockHandlerAction
{
    [self.message setText:sLabel];
    [self.btnAction setTitle:sButtonText forState:UIControlStateNormal];
    [self.btnAction addTarget:self action:@selector(buttonAction:) forControlEvents:UIControlEventTouchUpInside];
}

- (void)buttonAction:(id)sender {
    dispatch_async(dispatch_get_main_queue(), self.handlerAction);
}

@end


