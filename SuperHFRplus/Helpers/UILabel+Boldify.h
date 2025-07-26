//
//  UILabel+Boldify.h
//  SuperHFRplus
//
//  Created by Bruno ARENE on 28/06/2020.
//
#import <UIKit/UIKit.h>

@interface UILabel(Boldify);

- (void) boldSubstring: (NSString*) substring;
- (void) boldRange: (NSRange) range;

@end
