//
//  SmileyAlertView.m
//  SmileyAlertView
//
//  Created by Bruno ARENE on 19/09/2021.
//

#import <Foundation/Foundation.h>
#import "SmileyAlertView.h"
#import "ThemeManager.h"
#import "UIImage+GIF.h"
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
    
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:nil message:[NSString stringWithFormat:@"\n\n\n\n\n%@", sSmileyCode]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    NSString* sActionName = @"Ajouter aux favoris";
    if (!self.bAddSmiley) {
        sActionName = @"Retirer des favoris";
    }

    UIAlertAction* actionYes = nil;
    if (self.bAddSmiley) {
        actionYes = [UIAlertAction actionWithTitle:sActionName style:UIAlertActionStyleDefault
                                           handler:^(UIAlertAction * action) { [self addToFavoriteSmileys]; }];
    }
    else {
        actionYes = [UIAlertAction actionWithTitle:sActionName style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction * action) { [self removeFromFavoriteSmileys]; }];
    }
    UIAlertAction* actionDel = [UIAlertAction actionWithTitle:@"Annuler" style:UIAlertActionStyleCancel
                                                      handler:^(UIAlertAction * action) { }];
    self.actionSmileyCode = [UIAlertAction actionWithTitle:@"Mots clés" style:UIAlertActionStyleDefault
                                               handler:^(UIAlertAction * action) { [self showSmileyKeywords:vc]; }];
    [self.actionSmileyCode setEnabled:NO];
    
    if (bShowAction) {
        [alert addAction:actionYes];
    }
    [alert addAction:self.actionSmileyCode];
    [alert addAction:actionDel];
    NSURL *url = [NSURL URLWithString:[sSmileyImgUrl stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]]];
    NSData *data = [NSData dataWithContentsOfURL:url];
    UIImage *bkgImg;

    CGFloat f = 1.45;
    CGFloat w = f*70;
    CGFloat h = f*50;
    UIImageView *imageView = nil;

    if (data) {
        bkgImg = [UIImage sd_animatedGIFWithData:data];
        CGFloat w2 = bkgImg.size.width;
        CGFloat h2 = bkgImg.size.height;
        NSLog(@"Image w:%f h:%f", w2, h2);
        if (f*bkgImg.size.height/bkgImg.size.width*70 <= 50) {
            w = f*70;
            h = f*bkgImg.size.height/bkgImg.size.width*70;
            imageView = [[UIImageView alloc] initWithFrame:CGRectMake(85, 20+(f*50-h)/2, w, h)];
        }
        else {
            w = f*bkgImg.size.width/bkgImg.size.height*50;
            h = f*50;
            imageView = [[UIImageView alloc] initWithFrame:CGRectMake(85+(f*70-w)/2, 20, w, h)];
        }
    }
    else {
        f = 0.5;
        bkgImg = [UIImage imageNamed:@"clear"];
        w = f*bkgImg.size.width/bkgImg.size.height*50;
        h = f*50;
        imageView = [[UIImageView alloc] initWithFrame:CGRectMake(85+(100-w)/2, 40, w, h)];
    }
        
    //NSLog(@"W:%f X:%f (%@) w:%f h:%f", alert.view.frame.size.width, (alert.view.frame.size.width - 70)/2, NSStringFromCGRect(alert.view.frame), w, h);
    [imageView setImage:bkgImg];
    [alert.view addSubview:imageView];
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
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://forum.hardware.fr/wikismilies.php?config=hfr.inc&detail=%@", [self.sSelectedSmileyCode stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]]]];
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
