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
- (void) displaySmileyAjouterCancel:(NSString *)sSmileyCode withUrl:(NSString *)sSmileyImgUrl showKeyworkds:(BOOL)bShowKeywords baseController:(UIViewController*)vc
{
    self.bAddSmiley = YES;
    self.bShowKeywords = bShowKeywords;
    [self displaySmileyActionCancel:(NSString*)sSmileyCode withUrl:(NSString*)sSmileyImgUrl
                     handlerOK:^(UIAlertAction * action) { [self addAsPersonalSmileyConfirm]; }
                     handlerCancel:nil
                     baseController:(UIViewController*)vc];
}

- (void) displaySmileyRetirerCancel:(NSString *)sSmileyCode withUrl:(NSString *)sSmileyImgUrl showKeyworkds:(BOOL)bShowKeywords baseController:(UIViewController*)vc
{
    self.bAddSmiley = NO;
    self.bShowKeywords = bShowKeywords;
    [self displaySmileyActionCancel:(NSString*)sSmileyCode withUrl:(NSString*)sSmileyImgUrl
                     handlerOK:^(UIAlertAction * action) { [self addAsPersonalSmileyConfirm]; }
                     handlerCancel:nil
                     baseController:(UIViewController*)vc];
}


- (void) displaySmileyActionCancel:(NSString *)sSmileyCode withUrl:(NSString *)sSmileyImgUrl handlerOK:(void (^ __nullable)(UIAlertAction *action))handlerOK handlerCancel:(void (^ __nullable)(UIAlertAction *action))handlerCancel baseController:(UIViewController*)vc
{
    self.sSelectedSmileyCode = sSmileyCode;
    self.sSelectedSmileyImageURL = sSmileyImgUrl;
    
    NSLog(@"Selected smiley:%@ url:%@", sSmileyCode, sSmileyImgUrl);
    
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:nil message:[NSString stringWithFormat:@"\n\n\n\n\n%@", sSmileyCode]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    NSString* sActionName = @"Ajouter aux favoris";
    if (!self.bAddSmiley) {
        sActionName = @"Retirer des favoris";
    }

    UIAlertAction* actionYes = [UIAlertAction actionWithTitle:sActionName style:UIAlertActionStyleDefault
                                                      handler:^(UIAlertAction * action) { [self addAsPersonalSmileyConfirm]; }];
    UIAlertAction* actionDel = [UIAlertAction actionWithTitle:@"Annuler" style:UIAlertActionStyleCancel
                                                      handler:^(UIAlertAction * action) { }];
    if (self.bShowKeywords) {
        self.actionSmileyCode = [UIAlertAction actionWithTitle:@"Mot(s) clé(s)" style:UIAlertActionStyleDefault
                                                   handler:^(UIAlertAction * action) { [self showSmileyKeywords:vc]; }];
        [self.actionSmileyCode setEnabled:NO];
    }
    //[alert addAction:actionYes];
    if (self.bShowKeywords) {
        [alert addAction:self.actionSmileyCode];
    }
    [alert addAction:actionDel];
    NSURL *url = [NSURL URLWithString:sSmileyImgUrl];
    NSData *data = [NSData dataWithContentsOfURL:url];
    if (data) {
        UIImage *bkgImg = [UIImage sd_animatedGIFWithData:data];
        CGFloat f = 1.45;
        CGFloat w = f*70;
        CGFloat h = f*50;
        UIImageView *imageView = nil;
        
        CGFloat w2 = bkgImg.size.width;
        CGFloat h2 = bkgImg.size.height;
        NSLog(@"Image w:%f h:%f", w2, h2);
        //ori if (bkgImg.size.width/bkgImg.size.height > 70/50) {
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
        NSLog(@"W:%f X:%f (%@) w:%f h:%f", alert.view.frame.size.width, (alert.view.frame.size.width - 70)/2, NSStringFromCGRect(alert.view.frame), w, h);
        [imageView setImage:bkgImg];
        [alert.view addSubview:imageView];
        if (self.bShowKeywords) {
            [self requestSmileyCode];
        }
        [vc presentViewController:alert animated:YES completion:nil];
        [[ThemeManager sharedManager] applyThemeToAlertController:alert];
    }
}


- (void)addAsPersonalSmileyConfirm
{
    if (self.bAddSmiley) {
        [HFRAlertView DisplayOKCancelAlertViewWithTitle:@"Ajouter ce smiley aux souriards perso ?"
                                          andMessage:nil
                                          handlerOK:^(UIAlertAction * action) {[self addAsPersonalSmiley];}];
    }
    else
    {
        [HFRAlertView DisplayOKCancelAlertViewWithTitle:@"Retirer ce smiley des souriards perso ?"
                                          andMessage:nil
                                          handlerOK:^(UIAlertAction * action) {[self removeFromPersonalSmiley];}];
    }
}

- (void)addAsPersonalSmiley
{
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
    }
}

- (void)removeFromPersonalSmiley
{
    
    // Note ezzz: currently not working. Request returns nil :/ Surely an issue with the parameter codehex missing.
    /*
     <form name="test" action="supprperso_validation.php?config=hfr.inc&amp;codehex=9219174314d59fb81e5c1b0369d65559" method="post">
    <input type="hidden" name="hash_check" value="3e64a94aabae7c490aff10da4da92036"><table class="main hfr4kMainTab" cellspacing="0" cellpadding="4">
        <tbody><tr class="cBackHeader">
            <th colspan="3">Enlever un  smilie personnalisé de votre liste des favoris</th>
        </tr>
        <tr class="cBackHeader">
            <th>Ce que vous allez taper</th>
            <th>Le smilie qui va apparaitre</th>
            <th>Del.</th>
        </tr>
        <tr class="s2Topic">
            <th class="cBackTab2">[:casediscute]</th>
            <th class="cBackTab1"><img src="https://forum-images.hardware.fr/images/perso/casediscute.gif" alt="[:casediscute]"></th>
            <th class="cBackTab1"><input type="hidden" name="smiley0" value="[:casediscute]"><input type="checkbox" name="delete0"></th>
        </tr>

    <input type="submit" value="Supprimer les smilies de votre liste de smilies préférés">
    </form>*/
    
    
    NSString* s = @"https://forum.hardware.fr/user/supprperso_validation.php?config=hfr.inc";

    ASIFormDataRequest  *arequest = [[ASIFormDataRequest  alloc]  initWithURL:[NSURL URLWithString:s]];
    [arequest setPostValue:[[HFRplusAppDelegate sharedAppDelegate] hash_check] forKey:@"hash_check"];
    [arequest setPostValue:[self.sSelectedSmileyCode stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]] forKey:@"smiley0"];
    [arequest setPostValue:@"1" forKey:@"delete0"];
    [arequest startSynchronous];
    
    if (arequest) {
        if ([arequest error]) {
            // Popup erreur
            [HFRAlertView DisplayAlertViewWithTitle:@"Oooops !" andMessage:@"Smiley non retiré :'(" forDuration:(long)1 completion:nil];
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

            self.smileyCodeTableViewController.arrCodeList = [[trimmedString componentsSeparatedByString:@" "] copy];
            if (self.smileyCodeTableViewController.arrCodeList.count > 0) {
                self.smileyCodeTableViewController.sSmileyName = self.sSelectedSmileyCode;
                if (self.bShowKeywords) {
                    [self.actionSmileyCode setEnabled:YES];
                }
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
