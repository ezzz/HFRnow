//
//  MPViewController.m
//  HFRplus
//
//  Created by FLK on 23/07/10.
//

#import "HFRplusAppDelegate.h"

#import "HFRMPViewController.h"
#import "MessagesTableViewController.h"

#import "Topic.h"
#import "TopicCellView.h"

#import "ThemeManager.h"
#import "ThemeColors.h"
#import "MPStorage.h"
#import "TopicMPCellView.h"
#import <CommonCrypto/CommonDigest.h>
#import "UIImage+GIF.h"
#import "BlackList.h"

@implementation HFRMPViewController
@synthesize reloadOnAppear, actionButton, reloadButton;

 // The designated initializer.  Override if you create the controller programmatically and want to perform customization that is not appropriate for viewDidLoad.
/*
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if ((self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])) {
        // Custom initialization
    }
    return self;
}
*/

/*
// Implement loadView to create a view hierarchy programmatically, without using a nib.
- (void)loadView {
}
*/

- (void)fetchContent
{
    [super fetchContent];
    [[MPStorage shared] reloadMPStorageAsynchronous];
}


// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidLoad {
	//NSLog(@"vdl MP");

    UINib *nibCellMP = [UINib nibWithNibName:@"TopicMPCellView" bundle:nil];
    [self.topicsTableView registerNib:nibCellMP forCellReuseIdentifier:@"TopicMPCellID"];

    
	self.forumName = @"Messages";
	self.forumBaseURL = @"/forum1.php?config=hfr.inc&cat=prive&page=1";

    [super viewDidLoad];


    self.navigationItem.titleView = nil;
    //if([self isKindOfClass:[HFRMPViewController class]]) 
    
    [self showBarButton:kNewTopic];
    [self showBarButton:kReload];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(LoginChanged:)
                                                 name:kLoginChangedNotification
                                               object:nil];
}

/*
// Override to allow orientations other than the default portrait orientation.
- (BOOL)shouldAutorotateToInterfaceOrientation:(UIInterfaceOrientation)interfaceOrientation {
    // Return YES for supported orientations
    return (interfaceOrientation == UIInterfaceOrientationPortrait);
}
*/

- (void)didReceiveMemoryWarning {
    // Releases the view if it doesn't have a superview.
    [super didReceiveMemoryWarning];
    
    // Release any cached data, images, etc that aren't in use.
}

-(void)LoginChanged:(NSNotification *)notification {
    NSLog(@"loginChanged %@", notification);
    
    self.reloadOnAppear = YES;
}

- (void)viewWillAppear:(BOOL)animated {
    //NSLog(@"viewWillAppear Forums Table View");
    
    
    [super viewWillAppear:animated];

    if (self.reloadOnAppear) {
        [self fetchContent];
        self.reloadOnAppear = NO;
    }
    
    //On repositionne les boutons
    [self showBarButton:kSync];
}

// Customize the appearance of table view cells.
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
	TopicMPCellView *cell = [tableView dequeueReusableCellWithIdentifier:@"TopicMPCellID"];
    
    // Content
    TopicCellView *tmpCell = (TopicCellView*)[super tableView:tableView cellForRowAtIndexPath:indexPath];
    cell.timeLabel.text = tmpCell.timeLabel.text;
    
    if ([[(Topic *)[arrayData objectAtIndex:indexPath.row] aAuthorOrInter] containsString:@"multiples"]) {
        [cell.msgLabel setText:@"Interlocuteurs multiples"];
        [cell.msgLabel setFont:[UIFont systemFontOfSize:12.0]];
        cell.imgAvatar.image = [ThemeColors avatarGroup];
    }
    else {
        NSString* sPseudo = [(Topic *)[arrayData objectAtIndex:indexPath.row] aAuthorOrInter];
        [cell.msgLabel setText:[NSString stringWithFormat:@"%@", sPseudo]];
        [cell.msgLabel setFont:[UIFont systemFontOfSize:12.0]];
        UIImage* imgAvatarPseudo = [self getAvatarFromPseudo:sPseudo];
        if (imgAvatarPseudo) {
            cell.imgAvatar.image = imgAvatarPseudo;
            cell.imgAvatar.contentMode = UIViewContentModeScaleAspectFill;
        }
        else { // Default avatar
            cell.imgAvatar.image = [ThemeColors avatar];
        }
        
        cell.isPseudoInLoveList = NO;
        if ([[BlackList shared] isWL:[sPseudo lowercaseString]]) {
            cell.isPseudoInLoveList = YES;
        }
    }
    
    Topic *aTopic = [arrayData objectAtIndex:indexPath.row];
    cell.topicViewed = [aTopic isViewed];

    // Style
    UIFont *font1 = [UIFont boldSystemFontOfSize:13.0f];
    cell.timeLabel.textColor = [ThemeColors tintColor];
    if (cell.topicViewed) {
        font1 = [UIFont systemFontOfSize:13.0f];
        cell.timeLabel.textColor = [ThemeColors textColor2];
    }
    NSDictionary *arialDict = [NSDictionary dictionaryWithObject: font1 forKey:NSFontAttributeName];
    NSMutableAttributedString *aAttrString1 = [[NSMutableAttributedString alloc] initWithString:[aTopic aTitle] attributes: arialDict];
    UIFont *font2 = [UIFont fontWithName:@"fontello" size:15];
    NSMutableAttributedString *finalString = [[NSMutableAttributedString alloc]initWithString:@""];
    
    if (aTopic.isClosed) {
        UIColor *fontcC = [UIColor colorWithHex:@"#4A4A4A" alpha:1.0];
        NSDictionary *arialDict2c = [NSDictionary dictionaryWithObjectsAndKeys:font2, NSFontAttributeName, fontcC, NSForegroundColorAttributeName, nil];
        NSMutableAttributedString *aAttrString2C = [[NSMutableAttributedString alloc] initWithString:@" " attributes: arialDict2c];
        [finalString appendAttributedString:aAttrString2C];
    }
    [finalString appendAttributedString:aAttrString1];
    cell.titleLabel.attributedText = finalString;

    cell.isTopicViewedByReceiver = YES;
    if ([cell.titleLabel.text hasPrefix:@"[non lu]"]) {
        NSLog(@"Title: %@ is NON LU", cell.titleLabel.text);
        cell.isTopicViewedByReceiver = NO;
    }
    
    [finalString appendAttributedString:aAttrString1];
    
    
    return cell;
}

- (UIImage*)getAvatarFromPseudo:(NSString*)pseudo
{
    UIImage *image = nil;
    
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *diskCachePath = [[[paths objectAtIndex:0] stringByAppendingPathComponent:@"cache"] stringByAppendingPathComponent:@"avatars"];

    const char *str = [[pseudo lowercaseString] UTF8String];
    if (str) {
        unsigned char r[CC_MD5_DIGEST_LENGTH];
        CC_MD5(str, strlen(str), r);
        NSString *filename = [NSString stringWithFormat:@"%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
                              r[0], r[1], r[2], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10], r[11], r[12], r[13], r[14], r[15]];
        
        NSString *keyPathOfImage = [diskCachePath stringByAppendingPathComponent:filename];
        //NSLog(@"MP Avatar for (%@/%s) %ld : keyPathOfImage:%@", pseudo, str, strlen(str), keyPathOfImage);
        BOOL bLoadAvatar = NO;
        if ([fileManager fileExistsAtPath:keyPathOfImage]) // on check si on a deja l'avatar pour cette key
        {
            NSData *dataOfAvatar = [[NSData alloc] initWithContentsOfFile:keyPathOfImage];
            if (dataOfAvatar) {
                image = [UIImage sd_animatedGIFWithData:dataOfAvatar];
            }
        }
    }
    return image;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    NSString * sOpennedUrl = nil;
    
    // Try to get URL from MPStorage
    BOOL bCanSaveDrapalInMPStorage = NO;
    NSString *sPost = nil;
    if ([[NSUserDefaults standardUserDefaults] boolForKey:@"mpstorage_active"]) {
        // Get post id from URL
        Topic *t = [arrayData objectAtIndex:indexPath.row];
        if ([t.aAuthorOrInter isEqualToString:@"Interlocuteurs multiples"]) {
            bCanSaveDrapalInMPStorage = YES;
            for (NSString *qs in [t.aURL componentsSeparatedByString:@"&"]) {
                // Get the parameter name
                NSString *key = [[qs componentsSeparatedByString:@"="] objectAtIndex:0];
                // Get the parameter value
                if ([key isEqualToString:@"post"]) {
                    sPost = [[qs componentsSeparatedByString:@"="] objectAtIndex:1];
                }
            }
        
            if (sPost) {
                sOpennedUrl = [[MPStorage shared] getUrlFlagForTopidId:[sPost intValue]];
                if ([sOpennedUrl hasPrefix:@"https://forum.hardware.fr"]) {
                    sOpennedUrl = [sOpennedUrl substringWithRange:NSMakeRange(25, [sOpennedUrl length]-25)];
                }
            }
        }
    }
    // If nothing, only get URL of last page
    if (sOpennedUrl == nil) {
        sOpennedUrl = [[arrayData objectAtIndex:indexPath.row] aURLOfLastPost];
    }
    
	MessagesTableViewController *aView = [[MessagesTableViewController alloc] initWithNibName:@"MessagesTableViewController" bundle:nil andUrl:sOpennedUrl displaySeparator:YES];
	self.messagesTableViewController = aView;
	
	//setup the URL
	self.messagesTableViewController.topicName = [[arrayData objectAtIndex:indexPath.row] aTitle];	
	self.messagesTableViewController.isViewed = [[arrayData objectAtIndex:indexPath.row] isViewed];	
    self.messagesTableViewController.canSaveDrapalInMPStorage = bCanSaveDrapalInMPStorage;
    
    [self pushTopic];
	//NSLog(@"push message liste");

}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	return [NSString stringWithFormat:@"page %d", [self pageNumber]];
}

-(void)handleLongPress:(UILongPressGestureRecognizer*)longPressRecognizer {
	if (longPressRecognizer.state == UIGestureRecognizerStateBegan) {
		CGPoint longPressLocation = [longPressRecognizer locationInView:self.topicsTableView];
		self.pressedIndexPath = [[self.topicsTableView indexPathForRowAtPoint:longPressLocation] copy];
		
        if (topicActionAlert != nil) {
            topicActionAlert = nil;
        }
        
        NSMutableArray *arrayActionsMessages = [NSMutableArray array];
        [arrayActionsMessages addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"la dernière page", @"lastPageAction", nil] forKeys:[NSArray arrayWithObjects:@"title", @"code", nil]]];
        [arrayActionsMessages addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"la première page", @"firstPageAction", nil] forKeys:[NSArray arrayWithObjects:@"title", @"code", nil]]];
        [arrayActionsMessages addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"la page numéro...", @"chooseTopicPage", nil] forKeys:[NSArray arrayWithObjects:@"title", @"code", nil]]];
        [arrayActionsMessages addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"Copier le lien", @"copyLinkAction", nil] forKeys:[NSArray arrayWithObjects:@"title", @"code", nil]]];
        
        topicActionAlert = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        
        for( NSDictionary *dico in arrayActionsMessages) {
            [topicActionAlert addAction:[UIAlertAction actionWithTitle:[dico valueForKey:@"title"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                if ([self respondsToSelector:NSSelectorFromString([dico valueForKey:@"code"])])
                {
                    //[self performSelector:];
                    [self performSelectorOnMainThread:NSSelectorFromString([dico valueForKey:@"code"]) withObject:nil waitUntilDone:NO];
                }
                else {
                    NSLog(@"CRASH not respondsToSelector %@", [dico valueForKey:@"code"]);
                    
                    [self performSelectorOnMainThread:NSSelectorFromString([dico valueForKey:@"code"]) withObject:nil waitUntilDone:NO];
                }
            }]];
        }
        
        
        
        
        CGPoint longPressLocation2 = [longPressRecognizer locationInView:[[[HFRplusAppDelegate sharedAppDelegate] splitViewController] view]];
        CGRect origFrame = CGRectMake( longPressLocation2.x, longPressLocation2.y, 1, 1);
        
        
        if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPhone) {
            // Can't use UIAlertActionStyleCancel in dark theme : https://stackoverflow.com/a/44606994/1853603
            UIAlertActionStyle cancelButtonStyle = [[ThemeManager sharedManager] cancelAlertStyle];
            [topicActionAlert addAction:[UIAlertAction actionWithTitle:@"Annuler" style:cancelButtonStyle handler:^(UIAlertAction *action) {
                [self dismissViewControllerAnimated:YES completion:nil];
            }]];
        } else {
            // Required for UIUserInterfaceIdiomPad
            topicActionAlert.popoverPresentationController.sourceView = [[[HFRplusAppDelegate sharedAppDelegate] splitViewController] view];
            topicActionAlert.popoverPresentationController.sourceRect = origFrame;
            topicActionAlert.popoverPresentationController.backgroundColor = [ThemeColors alertBackgroundColor:[[ThemeManager sharedManager] theme]];
        }
        
        [self presentViewController:topicActionAlert animated:YES completion:nil];
        [[ThemeManager sharedManager] applyThemeToAlertController:topicActionAlert];
        
    }
}

-(void)lastPageAction{
    MessagesTableViewController *aView = [[MessagesTableViewController alloc] initWithNibName:@"MessagesTableViewController" bundle:nil andUrl:[[arrayData objectAtIndex:pressedIndexPath.row] aURLOfLastPage]];
    self.messagesTableViewController = aView;
    
    self.messagesTableViewController.topicName = [[arrayData objectAtIndex:pressedIndexPath.row] aTitle];
    self.messagesTableViewController.isViewed = [[arrayData objectAtIndex:pressedIndexPath.row] isViewed];
    
    [self pushTopic];
    
    //NSLog(@"url pressed last page: %@", [[arrayData objectAtIndex:pressedIndexPath.row] aURLOfLastPage]);
}

-(void)firstPageAction{
    MessagesTableViewController *aView = [[MessagesTableViewController alloc] initWithNibName:@"MessagesTableViewController" bundle:nil andUrl:[[arrayData objectAtIndex:pressedIndexPath.row] aURL]];
    self.messagesTableViewController = aView;
    
    self.messagesTableViewController.topicName = [[arrayData objectAtIndex:pressedIndexPath.row] aTitle];
    self.messagesTableViewController.isViewed = [[arrayData objectAtIndex:pressedIndexPath.row] isViewed];
    
    [self pushTopic];
    
    //NSLog(@"url pressed last post: %@", [[arrayData objectAtIndex:pressedIndexPath.row] aURL]);
}


-(void)reset
{
	[super reset];

	//[self.topicsTableView setHidden:YES];
	//[self.maintenanceView setHidden:YES];	
	//[self.loadingView setHidden:YES];	
	

    [self statusBarButton:kNewTopic enable:NO];
}


-(void)loadDataInTableView:(NSData *)contentData {
	[super loadDataInTableView:contentData];
    [self statusBarButton:kNewTopic enable:NO];

}

- (void)fetchContentStarted:(ASIHTTPRequest *)theRequest
{
	//Bouton Stop
    [self showBarButton:kCancel];
    [self statusBarButton:kNewTopic enable:NO];

	[super fetchContentStarted:theRequest];
}

- (void)fetchContentComplete:(ASIHTTPRequest *)theRequest
{

	//Bouton Reload
    [self showBarButton:kReload];
	
	[super fetchContentComplete:theRequest];

    
    
	switch (self.status) {
		case kMaintenance:
		case kNoAuth:
            [self statusBarButton:kNewTopic enable:NO];
			break;
		case kNoResults:            
		default:
            [self statusBarButton:kNewTopic enable:YES];
			break;
	}
    
    // TODOMP
    // Start asynchronous request for MP drapals
}

- (void)fetchContentFailed:(ASIHTTPRequest *)theRequest
{
    NSLog(@"fetchContentFailed");
	//Bouton Reload
    [self showBarButton:kReload];
	
	[super fetchContentFailed:theRequest];
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
	return 55;
}

-(void)statusBarButton:(BARBTNTYPE)type enable:(bool)enable {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSInteger vos_sujets = [defaults integerForKey:@"main_gaucheWIP"];

    
    
    if ((UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad && [self respondsToSelector:@selector(traitCollection)] && [HFRplusAppDelegate sharedAppDelegate].window.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact) ||
        vos_sujets == 0) {
        
        switch (type) {
            case kNewTopic:
            default:
            {
                //NSLog(@"NEW TOPIC");
                [self.navigationItem.leftBarButtonItem setEnabled:enable];
                [self.actionButton setEnabled:enable];
            }
                break;

        }
    }
    else {
        //NSLog(@"à gauche");
        
        switch (type) {
            case kNewTopic:
            default:
                
            {
                //NSLog(@"NEW TOPIC");
                [self.navigationItem.rightBarButtonItem setEnabled:enable];
                [self.actionButton setEnabled:enable];

            }
                break;

        }
        
        
    }
}

-(void)showBarButton:(BARBTNTYPE)type {
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSInteger vos_sujets = [defaults integerForKey:@"main_gaucheWIP"];
    //NSLog(@"maingauche %d", (vos_sujets == 0));
    //NSLog(@"maingauche %d", ([self respondsToSelector:@selector(traitCollection)] && [HFRplusAppDelegate sharedAppDelegate].window.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact));
    
    if (type == kSync) {
        //On inverse les boutons
        if ((UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad && [self respondsToSelector:@selector(traitCollection)] && [HFRplusAppDelegate sharedAppDelegate].window.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact) ||
            vos_sujets == 0) {
            //NSLog(@"DROITE ");
            if (!(self.navigationItem.leftBarButtonItem.action == @selector(newTopic))) {
                self.navigationItem.rightBarButtonItem = self.navigationItem.leftBarButtonItem;
                self.navigationItem.leftBarButtonItem = self.actionButton;
            }

            
        }
        else {
            //NSLog(@"GAUCHE");
            
            if ((self.navigationItem.leftBarButtonItem.action == @selector(newTopic))) {
                //NSLog(@"IN GAUCHE");
                self.navigationItem.leftBarButtonItem = self.navigationItem.rightBarButtonItem;
                self.navigationItem.rightBarButtonItem = self.actionButton;
            }
            

        }
        
        return;
    }
    
    
    
    
    
    if ((UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad && [self respondsToSelector:@selector(traitCollection)] && [HFRplusAppDelegate sharedAppDelegate].window.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact) ||
        vos_sujets == 0) {
        //NSLog(@"à droite");
        
        switch (type) {
            case kNewTopic:
            {
                //NSLog(@"NEW TOPIC");
                self.actionButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:self action:@selector(newTopic)];
                self.navigationItem.leftBarButtonItem = self.actionButton;
            }
                break;
            case kCancel:
            {
                //NSLog(@"CANCEL");
                self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop target:self action:@selector(cancelFetchContent)];
            }
                break;
            case kReload:
            default:
            {
                //NSLog(@"RELOAD");
                self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(fetchContent)];
            }
                break;
        }
    }
    else {
        //NSLog(@"à gauche");
        
        switch (type) {
            case kNewTopic:
            {
               //NSLog(@"NEW TOPIC");
                self.actionButton = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemCompose target:self action:@selector(newTopic)];
                self.navigationItem.rightBarButtonItem = self.actionButton;
            }
                break;
            case kCancel:
            {
                //NSLog(@"CANCEL");
                self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemStop target:self action:@selector(cancelFetchContent)];
            }
                break;
            case kReload:
            default:
            {
                //NSLog(@"RELOAD");
                self.navigationItem.leftBarButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemRefresh target:self action:@selector(fetchContent)];
            }
                break;
        }
        
        
    }
}

-(NSString *)newTopicTitle
{
	return @"Nouv. Message";	
}

@end
