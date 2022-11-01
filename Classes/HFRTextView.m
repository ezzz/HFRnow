//
//  HFRTextView.m
//  HFRplus
//
//  Created by FLK on 13/09/2015.
//
//

#import "HFRTextView.h"
#import "UIMenuItem+CXAImageSupport.h"
#import "HFRplusAppDelegate.h"
#import "ThemeColors.h"
#import "ThemeManager.h"

@implementation HFRTextView

-(void)awakeFromNib
{
    NSLog(@"awakeFromNib");
    [super awakeFromNib]; // Don't forget to call super
    
    // On rajoute les menus pour le style
    self.keyboardAppearance = [ThemeColors keyboardAppearance:[[ThemeManager sharedManager] theme]];
}

- (UIMenu *)menuForHFRTextView:(UITextView *)textView editMenuForTextInRange:(NSRange)range suggestedActions:(NSArray<UIMenuElement *> *)suggestedActions
{
    //Do more intitialization here
    NSString* sSuffix = @"";
    if ([[ThemeManager sharedManager] theme] == ThemeLight) {
        sSuffix = @"-Inv";
    }

    UIImage *menuImgBold = [UIImage imageNamed:[NSString stringWithFormat:@"BoldEFilled-20%@", sSuffix]];
    UIImage *menuImgItalic = [UIImage imageNamed:[NSString stringWithFormat:@"ItalicFilled-20%@", sSuffix]];
    UIImage *menuImgUnderline = [UIImage imageNamed:[NSString stringWithFormat:@"UnderlineFilled-20%@", sSuffix]];
    UIImage *menuImgStrike = [UIImage imageNamed:[NSString stringWithFormat:@"StrikethroughFilled-20%@", sSuffix]];
    UIImage *menuImgSpoiler = [UIImage imageNamed:[NSString stringWithFormat:@"InvisibleFilled-20%@", sSuffix]];
    UIImage *menuImgQuote = [UIImage imageNamed:[NSString stringWithFormat:@"QuoteEFilled-20%@", sSuffix]];
    UIImage *menuImgLink = [UIImage imageNamed:[NSString stringWithFormat:@"LinkFilled-20%@", sSuffix]];
    UIImage *menuImgImage = [UIImage imageNamed:[NSString stringWithFormat:@"XlargeIconsFilled-20%@", sSuffix]];
    
    NSMutableArray<UIMenuElement *> *childrenList = [[NSMutableArray alloc] init];
    for (UIMenuElement* el in suggestedActions) {
        //NSLog(@"Element title : %@ / %@ / %@", el.title, el.subtitle, el.description);
        [childrenList addObject:el];
    }
    
    UIAction *action = [UIAction actionWithTitle:@"" image:menuImgBold identifier:nil  handler:^(__kindof UIAction * _Nonnull action) {
        [self insertBBCode:@"b"];
    }];
    [childrenList addObject:action];
    
    action = [UIAction actionWithTitle:@"" image:menuImgItalic identifier:nil  handler:^(__kindof UIAction * _Nonnull action) {
        [self insertBBCode:@"i"];
    }];
    [childrenList addObject:action];
    action = [UIAction actionWithTitle:@"" image:menuImgUnderline identifier:nil  handler:^(__kindof UIAction * _Nonnull action) {
        [self insertBBCode:@"u"];
    }];
    [childrenList addObject:action];
    action = [UIAction actionWithTitle:@"" image:menuImgStrike identifier:nil  handler:^(__kindof UIAction * _Nonnull action) {
        [self insertBBCode:@"strike"];
    }];
    [childrenList addObject:action];
    action = [UIAction actionWithTitle:@"" image:menuImgSpoiler identifier:nil  handler:^(__kindof UIAction * _Nonnull action) {
        [self insertBBCode:@"spoiler"];
    }];
    [childrenList addObject:action];
    action = [UIAction actionWithTitle:@"" image:menuImgQuote identifier:nil  handler:^(__kindof UIAction * _Nonnull action) {
        [self insertBBCode:@"quote"];
    }];
    [childrenList addObject:action];
    action = [UIAction actionWithTitle:@"" image:menuImgLink identifier:nil  handler:^(__kindof UIAction * _Nonnull action) {
        [self insertBBCode:@"url"];
    }];
    [childrenList addObject:action];
    action = [UIAction actionWithTitle:@"" image:menuImgImage identifier:nil  handler:^(__kindof UIAction * _Nonnull action) {
        [self insertBBCode:@"img"];
    }];
    action = [UIAction actionWithTitle:@"FIXED" image:nil identifier:nil  handler:^(__kindof UIAction * _Nonnull action) {
        [self insertBBCode:@"fixed"];
    }];
    [childrenList addObject:action];
    
    return [UIMenu menuWithTitle:@"" image:nil identifier:nil options:UIMenuOptionsDestructive children:childrenList];
}

// Enable to hide some menuitem for HFRTextView
- (BOOL)canPerformAction: (SEL)action withSender: (id)sender {
    BOOL bCanPerformAction = NO;
    
    if (action == @selector(cut:)) bCanPerformAction = [super canPerformAction:@selector(cut:) withSender:sender];
    if (action == @selector(copy:)) bCanPerformAction = [super canPerformAction:@selector(copy:) withSender:sender];
    if (action == @selector(paste:)) bCanPerformAction = [super canPerformAction:@selector(paste:) withSender:sender];
    
    if ([NSStringFromSelector(action) isEqualToString:@"replace:"]) bCanPerformAction = NO;
    if ([NSStringFromSelector(action) isEqualToString:@"_promptForReplace:"]) bCanPerformAction = NO;
    if ([NSStringFromSelector(action) isEqualToString:@"_findSelected:"]) bCanPerformAction = NO;
    NSLog(@"HFRTextView - CanPerformAction %@ > %s", NSStringFromSelector(action), bCanPerformAction ? "YES" : "NO");
    if (action == @selector(textCut:)) return [super canPerformAction:@selector(cut:) withSender:sender];
    if (action == @selector(textCopy:)) return [super canPerformAction:@selector(copy:) withSender:sender];
    if (action == @selector(textPaste:)) return [super canPerformAction:@selector(paste:) withSender:sender];
    
    if (action == @selector(cut:)) return [sender isKindOfClass:[UIKeyCommand class]] && [super canPerformAction:@selector(cut:) withSender:sender];
    if (action == @selector(copy:)) return [sender isKindOfClass:[UIKeyCommand class]] && [super canPerformAction:@selector(copy:) withSender:sender];
    if (action == @selector(select:)) return  [super canPerformAction:@selector(select:) withSender:sender];
    if (action == @selector(selectAll:)) return [super canPerformAction:@selector(selectAll:) withSender:sender];
    if (action == @selector(paste:)) return [sender isKindOfClass:[UIKeyCommand class]] && [super canPerformAction:@selector(paste:) withSender:sender];
    return bCanPerformAction;
}

// Remove Search web from UIMenu (it does not work when trying to remove it from canPerformAction)
- (void)buildMenuWithBuilder:(id<UIMenuBuilder>)builder  {
    [builder removeMenuForIdentifier:UIMenuLookup];
    [super buildMenuWithBuilder:builder];
}

- (void)insertBBCode:(NSString *)code {
    NSMutableString *localtext = [self.text mutableCopy];
    
    NSRange localSelectedRange = self.selectedRange;
    //NSLog(@"3 selectRng %lu %lu", (unsigned long)localSelectedRange.location, (unsigned long)localSelectedRange.length);
    
    //NSLog(@"selectedRange %d %d", selectedRange.location, selectedRange.location);
    
    bool wasSelected = NO;
    if (localSelectedRange.length) {
        wasSelected = YES;
    }
    
    [localtext insertString:[NSString stringWithFormat:@"[/%@]", code] atIndex:localSelectedRange.location+localSelectedRange.length];
    [localtext insertString:[NSString stringWithFormat:@"[%@]", code] atIndex:localSelectedRange.location];
    
    
    //NSLog(@"selectedRange %d %d", selectedRange.location, selectedRange.length);
    
    if (localSelectedRange.length > 0) {
        localSelectedRange.location += (code.length * 2) + 5 + localSelectedRange.length;
    }
    else {
        localSelectedRange.location += code.length + 2;
    }
    
    localSelectedRange.length = 0;
    
    
    
    self.text = localtext;
    self.selectedRange = localSelectedRange;
    [self.delegate textViewDidChange:self];
    
    if ([UIPasteboard generalPasteboard].string.length) {
        
        
        if ([code isEqualToString:@"url"] && wasSelected) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Insérer le contenu du presse-papier?"
                                                            message:[NSString stringWithFormat:@"%@", [UIPasteboard generalPasteboard].string]
                                                           delegate:self cancelButtonTitle:@"Non" otherButtonTitles:@"[url= Oui ]", nil];
            [alert setTag:668];
            [alert show];
        }
        else if ([code isEqualToString:@"url"] && !wasSelected) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Insérer le contenu du presse-papier?"
                                                            message:[NSString stringWithFormat:@"%@", [UIPasteboard generalPasteboard].string]
                                                           delegate:self cancelButtonTitle:@"Non" otherButtonTitles:@"Oui [url=XXX]", @"Oui [url]XXX[/url]", nil];
            [alert setTag:667];
            [alert show];
        }
        else if (!wasSelected) {
            UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Insérer le contenu du presse-papier?"
                                                            message:[NSString stringWithFormat:@"%@", [UIPasteboard generalPasteboard].string]
                                                           delegate:self cancelButtonTitle:@"Non" otherButtonTitles:@"Oui", nil];
            [alert setTag:666];
            [alert show];
        }

    }
    
}

- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex
{
    //NSLog(@"%ld = %ld", (long)buttonIndex, (long)alertView.tag);
    
    if ((buttonIndex == 1 && alertView.tag == 666) || (buttonIndex == 2 && alertView.tag == 667)) {
        NSRange localSelectedRange = self.selectedRange;
        //NSLog(@"1 selectRng %lu %lu", (unsigned long)localSelectedRange.location, (unsigned long)localSelectedRange.length);
        
        NSMutableString *localtext = [self.text mutableCopy];
        
        [localtext insertString:[NSString stringWithFormat:@"%@", [UIPasteboard generalPasteboard].string] atIndex:localSelectedRange.location];
        self.text = localtext;
        localSelectedRange.location += [UIPasteboard generalPasteboard].string.length;
        localSelectedRange.length = 0;
        self.selectedRange =  localSelectedRange;
        
        [self.delegate textViewDidChange:self];
        
    }
    else if (alertView.tag == 667 || alertView.tag == 668) {
        
        if (buttonIndex == 1) { //url=

            
            NSRange localSelectedRange = self.selectedRange;
            //NSLog(@"2 selectRng %lu %lu", (unsigned long)localSelectedRange.location, (unsigned long)localSelectedRange.length);
            NSMutableString *localtext = [self.text mutableCopy];

            //On cherche [url] backward
            NSRange rangeToSearch = NSMakeRange(0, localSelectedRange.location); // get a range without the space character
            NSRange rangeOfSecondToLastSpace = [localtext rangeOfString:@"[url]" options:NSBackwardsSearch range:rangeToSearch];

            
            
            [localtext insertString:[NSString stringWithFormat:@"=%@", [UIPasteboard generalPasteboard].string] atIndex:rangeOfSecondToLastSpace.location  + 4];

            localSelectedRange.location += [UIPasteboard generalPasteboard].string.length + 4;
            localSelectedRange.length = 0;
            
            self.text = localtext;
            self.selectedRange =  localSelectedRange;
            
            [self.delegate textViewDidChange:self];
        }
    }
}

@end
