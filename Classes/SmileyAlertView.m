//
//  SmileyAlertView.m
//  SmileyAlertView
//
//  Created by Bruno ARENE on 19/09/2021.
//

#import <Foundation/Foundation.h>
#import <SDWebImage/SDWebImage.h>
#import "SmileyAlertView.h"
#import "ThemeManager.h"
#import "SmileyCodeTableViewController.h"
#import "HFRAlertView.h"
#import "ASIHTTPRequest+Tools.h"
#import "RegexKitLite.h"
#import "HTMLParser.h"
#import "ASIFormDataRequest.h"
#import "HFRplusAppDelegate.h"
#import "SmileyCache.h"

@implementation SmileyAlertView

//@property sSelectedSmileyCode, sSelectedSmileyImageURL, actionSmileyCode, smileyCodeTableViewController;

static SmileyAlertView *_shared = nil;    // static instance variable

#pragma mark - Init methods

+ (SmileyAlertView *)shared {
    if (_shared == nil) {
        _shared = [[super allocWithZone:NULL] init];
    }
    return _shared;
}

- (id)init {
    if ( (self = [super init]) ) {
        // your custom initialization
    }
    return self;
}

#pragma mark - Smiley alertview methods
/*
- (void) displaySmileyActionCancel:(NSString *)sSmileyCode withUrl:(NSString *)sSmileyImgUrl
                         addSmiley:(BOOL)bAddSmiley
                        showAction:(BOOL)bShowAction
                       handlerDone:(dispatch_block_t)handlerDone
                     handlerFailed:(dispatch_block_t)handlerFailed
                 handlerSelectCode:(nsstring_block_t)handlerSelectCode
                    baseController:(UIViewController*)vc
{
    self.bAddSmiley = bAddSmiley;
    self.sSelectedSmileyCode = sSmileyCode;
    self.sSelectedSmileyImageURL = sSmileyImgUrl;
    self.handlerDone = handlerDone;
    self.handlerFailed = handlerFailed;
    self.handlerSelectCode = handlerSelectCode;
    NSLog(@"Selected smiley:%@ url:%@", sSmileyCode, sSmileyImgUrl);
    
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    NSString* sActionName = self.bAddSmiley ? @"Ajouter aux favoris" : @"Retirer des favoris";
    
    UIAlertAction* actionYes = nil;
    if (self.bAddSmiley) {
        actionYes = [UIAlertAction actionWithTitle:sActionName style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction * action) { [self addToFavoriteSmileys]; }];
    } else {
        actionYes = [UIAlertAction actionWithTitle:sActionName style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction * action) { [self removeFromFavoriteSmileys]; }];
    }
    UIAlertAction* actionDel = [UIAlertAction actionWithTitle:@"Annuler"
                                                        style:UIAlertActionStyleCancel
                                                      handler:^(UIAlertAction * action) { }];
    self.actionSmileyCode = [UIAlertAction actionWithTitle:@"Mots clés"
                                                     style:UIAlertActionStyleDefault
                                                   handler:^(UIAlertAction * action) { [self showSmileyKeywords:vc]; }];
    [self.actionSmileyCode setEnabled:NO];
    
    if (bShowAction) {
        [alert addAction:actionYes];
    }
    [alert addAction:self.actionSmileyCode];
    [alert addAction:actionDel];
    
    // Image du smiley
    NSURL *url = [NSURL URLWithString:[sSmileyImgUrl stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    CGFloat f = 1.5;
    CGFloat w = f*70;
    CGFloat h = f*50;

    UIImageView *imageView = [[UIImageView alloc] initWithFrame:CGRectMake(105, 20+(f*70-w)/2, w, h)];
    [imageView sd_setImageWithURL:url placeholderImage:nil];
    [imageView setContentMode:UIViewContentModeScaleAspectFit];
    [alert.view addSubview:imageView];
    
    NSMutableParagraphStyle *style = [[NSMutableParagraphStyle alloc] init];
    style.alignment = NSTextAlignmentCenter; // ou Left/Right
    NSAttributedString *attrMsg = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%@", sSmileyCode]
                                                                  attributes:@{NSParagraphStyleAttributeName: style}];

    [alert setValue:attrMsg forKey:@"attributedMessage"];

    [self requestSmileyCode];
    [vc presentViewController:alert animated:YES completion:nil];
    [[ThemeManager sharedManager] applyThemeToAlertController:alert];
}
*/

- (void) displaySmileyActionCancel:(NSString *)sSmileyCode
                           withUrl:(NSString *)sSmileyImgUrl
                         addSmiley:(BOOL)bAddSmiley
                        showAction:(BOOL)bShowAction
                       handlerDone:(dispatch_block_t)handlerDone
                     handlerFailed:(dispatch_block_t)handlerFailed
                 handlerSelectCode:(nsstring_block_t)handlerSelectCode
                    baseController:(UIViewController*)vc
{
    self.bAddSmiley = bAddSmiley;
    self.sSelectedSmileyCode = sSmileyCode;
    self.sSelectedSmileyImageURL = sSmileyImgUrl;
    self.handlerDone = handlerDone;
    self.handlerFailed = handlerFailed;
    self.handlerSelectCode = handlerSelectCode;
    NSLog(@"Selected smiley:%@ url:%@", sSmileyCode, sSmileyImgUrl);
    
    // ==== Alert de base ====
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:nil
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    NSString* sActionName = self.bAddSmiley ? @"Ajouter aux favoris" : @"Retirer des favoris";
    
    UIAlertAction* actionYes = nil;
    if (self.bAddSmiley) {
        actionYes = [UIAlertAction actionWithTitle:sActionName style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction * action) { [self addToFavoriteSmileys]; }];
    } else {
        actionYes = [UIAlertAction actionWithTitle:sActionName style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction * action) { [self removeFromFavoriteSmileys]; }];
    }
    
    UIAlertAction* actionDel = [UIAlertAction actionWithTitle:@"Annuler"
                                                        style:UIAlertActionStyleCancel
                                                      handler:^(UIAlertAction * action) { }];
    
    self.actionSmileyCode = [UIAlertAction actionWithTitle:@"Mots clés"
                                                     style:UIAlertActionStyleDefault
                                                   handler:^(UIAlertAction * action) { [self showSmileyKeywords:vc]; }];
    [self.actionSmileyCode setEnabled:NO];
    
    if (bShowAction) {
        [alert addAction:actionYes];
    }
    [alert addAction:self.actionSmileyCode];
    [alert addAction:actionDel];
    
    // ==== Création du contentViewController custom ====
    UIViewController *contentVC = [[UIViewController alloc] init];
    
    // Stack vertical pour image + label
    UIStackView *stack = [[UIStackView alloc] init];
    stack.axis = UILayoutConstraintAxisVertical;
    stack.alignment = UIStackViewAlignmentCenter;
    stack.spacing = 8;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    
    // Image
    NSURL *url = [NSURL URLWithString:[sSmileyImgUrl stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    UIImageView *imageView = [[UIImageView alloc] init];
    [imageView sd_setImageWithURL:url placeholderImage:nil];
    imageView.contentMode = UIViewContentModeScaleAspectFit;
    imageView.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [imageView.widthAnchor constraintEqualToConstant:105],
        [imageView.heightAnchor constraintEqualToConstant:70]
    ]];
    
    // Label
    UILabel *label = [[UILabel alloc] init];
    label.text = sSmileyCode;
    label.textAlignment = NSTextAlignmentCenter;
    label.numberOfLines = 0;
    
    // Ajout dans la stack
    [stack addArrangedSubview:imageView];
    [stack addArrangedSubview:label];
    
    // Ajout stack -> contentVC
    [contentVC.view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:contentVC.view.leadingAnchor constant:8],
        [stack.trailingAnchor constraintEqualToAnchor:contentVC.view.trailingAnchor constant:-8],
        [stack.topAnchor constraintEqualToAnchor:contentVC.view.topAnchor constant:20],
        [stack.bottomAnchor constraintEqualToAnchor:contentVC.view.bottomAnchor constant:0]
    ]];
    
    // Injection du VC custom dans l’alerte
    [alert setValue:contentVC forKey:@"contentViewController"];
    
    // ==== Présentation ====
    [self requestSmileyCode];
    [vc presentViewController:alert animated:YES completion:nil];
    [[ThemeManager sharedManager] applyThemeToAlertController:alert];
}

- (void)addToFavoriteSmileys
{                               
    if ([[SmileyCache shared] AddAndSaveDicFavoritesApp:self.sSelectedSmileyCode source:self.sSelectedSmileyImageURL addSmiley:YES]) {
        dispatch_async(dispatch_get_main_queue(), self.handlerDone);
    }
    else {
        dispatch_async(dispatch_get_main_queue(), self.handlerFailed);
    }

    /*
    NSString* s = @"https://forum.hardware.fr/user/addperso.php?config=hfr.inc";

    ASIFormDataRequest  *arequest = [[ASIFormDataRequest  alloc]  initWithURL:[NSURL URLWithString:s]];
    [arequest setPostValue:[[HFRplusAppDelegate sharedAppDelegate] hash_check] forKey:@"hash_check"];
    [arequest setPostValue:[self.sSelectedSmileyCode stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]] forKey:@"smilie"];
    [arequest startSynchronous];
    
    if (arequest) {
        if ([arequest error]) {
            // Popup erreur
            [HFRAlertView DisplayAlertViewWithTitle:@"Oooops !" andMessage:@"Smiley non ajouté ajouté :'(" forDuration:(long)1 completion:nil];
        }
        else if ([arequest safeResponseString])
        {
            NSLog(@"Smileys persos request: %@", [arequest safeResponseString]);
            NSError * error = nil;
            HTMLParser *myParser = [[HTMLParser alloc] initWithString:[arequest safeResponseString] error:&error];
            HTMLNode * bodyNode = [myParser body]; //Find the body tag
            HTMLNode * messagesNode = [bodyNode findChildWithAttribute:@"class" matchingName:@"hop" allowPartial:NO]; //Get all the <img alt="" />
            NSString* msg = [[messagesNode contents] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
            [HFRAlertView DisplayAlertViewWithTitle:nil andMessage:msg forDuration:(long)1 completion:nil];
        }
    }*/
}

- (void)removeFromFavoriteSmileys
{
    if ([[SmileyCache shared] AddAndSaveDicFavoritesApp:self.sSelectedSmileyCode source:self.sSelectedSmileyImageURL addSmiley:NO]) {
        dispatch_async(dispatch_get_main_queue(), self.handlerDone);
    }
    else {
        dispatch_async(dispatch_get_main_queue(), self.handlerFailed);
    }
}

- (void)requestSmileyCode
{
    //Url wiki details : https://forum.hardware.fr/wikismilies.php?config=hfr.inc&detail=%5B%3Aezzz%5D
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://forum.hardware.fr/wikismilies.php?config=hfr.inc&detail=%@", [self.sSelectedSmileyCode stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLPathAllowedCharacterSet]]]];
    ASIHTTPRequest* request = [ASIHTTPRequest requestWithURL:url];
    [request setShouldRedirect:NO];
    [request setDelegate:self];
    request.timeOutSeconds = 2;
    [request setDidFinishSelector:@selector(requestSmileyComplete:)];
    [request setDidFailSelector:@selector(requestSmileyFailed:)];
    [request startAsynchronous];
}

- (void)requestSmileyComplete:(ASIHTTPRequest *)request
{
    NSString* content = [request responseString];
    if (content) {
        @try {
            NSError *error;
            //NSLog(@"\n----------------------------------------------------\n%@\n----------------------------------------------------", content);
            HTMLParser *myParser = [[HTMLParser alloc] initWithString:content error:&error];
            HTMLNode * bodyNode = [myParser body]; //Find the body tag
            HTMLNode *inputNode = [bodyNode findChildWithAttribute:@"name" matchingName:@"keywords0" allowPartial:NO];
            NSString* text = [inputNode getAttributeNamed:@"value"];
            NSLog(@"Lol: %@", text);
        
            // Prepare next view
            if (self.smileyCodeTableViewController == nil)
            {
                self.smileyCodeTableViewController = [[SmileyCodeTableViewController alloc] init];
            }
            self.smileyCodeTableViewController.arrCodeList = [[NSMutableArray alloc] init];
            // Remove double spaces
            NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"  +" options:NSRegularExpressionCaseInsensitive error:&error];
            NSString *trimmedString = [regex stringByReplacingMatchesInString:text options:0 range:NSMakeRange(0, text.length) withTemplate:@" "];
            //Remove some specail characters
            [trimmedString stringByReplacingOccurrencesOfString:@"," withString:@""];
            self.smileyCodeTableViewController.arrCodeList = [[trimmedString componentsSeparatedByString:@" "] copy];
            if (self.smileyCodeTableViewController.arrCodeList.count > 0) {
                self.smileyCodeTableViewController.sSmileyName = self.sSelectedSmileyCode;
                self.smileyCodeTableViewController.handlerSelectCode = self.handlerSelectCode;
                [self.actionSmileyCode setEnabled:YES];
            }
        }
        @catch (NSException * e) {
            NSLog(@"Exception: %@", e);
        }
        @finally {}
    }
}

- (void)requestSmileyFailed:(ASIHTTPRequest *)request
{
    // Nothing to do
}

- (void)showSmileyKeywords:(UIViewController*)vc
{
    [vc.navigationController pushViewController:self.smileyCodeTableViewController animated:YES];
}

@end
