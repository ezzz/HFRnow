//
//  MPViewController.m
//  HFRplus
//
//  Created by FLK on 23/07/10.
//

#import "HFRplusAppDelegate.h"

#import "HFRMPViewController.h"
#import "TopicsTableViewController.h"
#import "MessagesTableViewController.h"

#import "Topic.h"
#import "TopicCellView.h"

#import "ThemeManager.h"
#import "ThemeColors.h"
#import "MPStorage.h"
#import "TopicMPCellView.h"
#import <CommonCrypto/CommonDigest.h>
#import "BlackList.h"
#import <SDWebImage/SDWebImage.h>

@implementation HFRMPViewController

//@synthesize reloadOnAppear, actionButton, reloadButton, detailNavigationViewController, arrayData, topicActionAlert, pressedIndexPath;

 // The designated initializer.  Override if you create the controller programmatically and want to perform customization that is not appropriate for viewDidLoad.

- (void)fetchContent
{
    [super fetchContent];
    [[MPStorage shared] reloadMPStorageAsynchronous];
}


// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
- (void)viewDidLoad {

    //NSLog(@"vdl MP");
    
    //UINib *nibCellMP = [UINib nibWithNibName:@"TopicMPCellView" bundle:nil];
    //[self.topicsTableView registerNib:nibCellMP forCellReuseIdentifier:@"TopicMPCellID"];
    
	self.forumName = @"Messages";
	self.forumBaseURL = @"/forum1.php?config=hfr.inc&cat=prive&page=1";

    //TODO : doit être placé après les lignes du dessus. Pas très propre
    // Et possiblement à l'origine du bug sur les ongletc Categories et Messages qui se mélangent...
    [super viewDidLoad];

    NSLog(@"SEARCH MP Registering nib for tableView: %@", self.topicsTableView);
    UINib *nib = [UINib nibWithNibName:@"TopicMPCellView" bundle:nil];
    [self.topicsTableView registerNib:nib forCellReuseIdentifier:@"TopicMPCellID"];

    self.navigationItem.titleView = nil;

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

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSInteger iSizeTextTopics = [[NSUserDefaults standardUserDefaults] integerForKey:@"size_text_topics"];
    return 55.0*iSizeTextTopics/100;
}

// Customize the appearance of table view cells.
- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger iSizeTextTopics = [[NSUserDefaults standardUserDefaults] integerForKey:@"size_text_topics"];

    //TopicMPCellView *cell = [tableView dequeueReusableCellWithIdentifier:@"TopicMPCellID"];
    //TopicMPCellView *cell = (TopicMPCellView *)[tableView dequeueReusableCellWithIdentifier:@"TopicMPCellID"];
    static NSString *CellIdentifier = @"TopicMPCellID";
    
    NSLog(@"Dequeue from tableView: %@", tableView);
    
    //TopicMPCellView *cell = (TopicMPCellView *)[tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    TopicMPCellView *cell = [tableView dequeueReusableCellWithIdentifier:@"TopicMPCellID" forIndexPath:indexPath];

    // Content
    Topic *aTopic = [self.arrayData objectAtIndex:indexPath.row];
    
    // Time label
    [cell.timeLabel setText:[NSString stringWithFormat:@"%@ - %@", [aTopic aAuthorOfLastPost], [aTopic aDateOfLastPost]]];
    [cell.timeLabel setFont:[UIFont systemFontOfSize:11.0*iSizeTextTopics/100]];

    cell.imgAvatar.layer.cornerRadius = cell.imgAvatar.frame.size.width / 2;
    cell.imgAvatar.clipsToBounds = YES;
    
    if ([[(Topic *)[self.arrayData objectAtIndex:indexPath.row] aAuthorOrInter] containsString:@"multiples"]) {
        [cell.msgLabel setText:@"Interlocuteurs multiples"];
        [cell.msgLabel setFont:[UIFont systemFontOfSize:12.0]];
        cell.imgAvatar.image = [ThemeColors avatarGroup];
    }
    else {
        NSString* sPseudo = [(Topic *)[self.arrayData objectAtIndex:indexPath.row] aAuthorOrInter];
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
    
    cell.topicViewed = [aTopic isViewed];

    // Style
    UIFont *font1 = [UIFont boldSystemFontOfSize:13.0f*iSizeTextTopics/100];
    //cell.timeLabel.textColor = [ThemeColors tintColor];
    if (cell.topicViewed) {
        font1 = [UIFont systemFontOfSize:13.0f*iSizeTextTopics/100];
        //cell.timeLabel.textColor = [ThemeColors textColor2];
    }


    NSDictionary *arialDict = [NSDictionary dictionaryWithObject: font1 forKey:NSFontAttributeName];
    NSMutableAttributedString *aAttrString1 = [[NSMutableAttributedString alloc] initWithString:[aTopic aTitle] attributes: arialDict];
    UIFont *font2 = [UIFont fontWithName:@"fontello" size:15.0*iSizeTextTopics/100];
    NSMutableAttributedString *finalString = [[NSMutableAttributedString alloc]initWithString:@""];
    
    cell.isTopicClosed = NO;
    if (aTopic.isClosed) {
        cell.isTopicClosed = YES;
        UIColor *fontcC = [UIColor colorWithHex:@"#4A4A4A" alpha:1.0];
        NSDictionary *arialDict2c = [NSDictionary dictionaryWithObjectsAndKeys:font2, NSFontAttributeName, fontcC, NSForegroundColorAttributeName, nil];
        NSMutableAttributedString *aAttrString2C = [[NSMutableAttributedString alloc] initWithString:@" " attributes: arialDict2c];
        [finalString appendAttributedString:aAttrString2C];
    }
    [finalString appendAttributedString:aAttrString1];
    cell.titleLabel.attributedText = finalString;

    cell.isTopicViewedByReceiver = YES;
    if ([cell.titleLabel.text hasPrefix:@"[non lu]"]) {
        cell.isTopicViewedByReceiver = NO;
    }
    
    [cell.msgLabel setFont:[UIFont systemFontOfSize:11.0f*iSizeTextTopics/100]];
    [cell.timeLabel setFont:[UIFont systemFontOfSize:11.0f*iSizeTextTopics/100]];
    
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
                image = [UIImage sd_imageWithGIFData:dataOfAvatar];
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
        Topic *t = [self.arrayData objectAtIndex:indexPath.row];
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
        sOpennedUrl = [[self.arrayData objectAtIndex:indexPath.row] aURLOfLastPost];
    }
    
    Topic* topic = [self.arrayData objectAtIndex:indexPath.row];
    self.messagesTableViewController = [[MessagesTableViewController alloc] init];
    self.messagesTableViewController.currentUrl = sOpennedUrl;
    self.messagesTableViewController.canSaveDrapalInMPStorage = bCanSaveDrapalInMPStorage;
    self.messagesTableViewController.topicName = topic.aTitle;
    self.messagesTableViewController.isViewed = topic.isViewed;
    
    [self pushTopic];
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
	return [NSString stringWithFormat:@"page %d", [self pageNumber]];
}

-(void)handleLongPress:(UILongPressGestureRecognizer*)longPressRecognizer {
	if (longPressRecognizer.state == UIGestureRecognizerStateBegan) {
		CGPoint longPressLocation = [longPressRecognizer locationInView:self.topicsTableView];
		self.pressedIndexPath = [[self.topicsTableView indexPathForRowAtPoint:longPressLocation] copy];
		
        if (self.topicActionAlert != nil) {
            self.topicActionAlert = nil;
        }
        
        NSMutableArray *arrayActionsMessages = [NSMutableArray array];
        [arrayActionsMessages addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"Dernière page", @"lastPageAction", nil] forKeys:[NSArray arrayWithObjects:@"title", @"code", nil]]];
        [arrayActionsMessages addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"Première page", @"firstPageAction", nil] forKeys:[NSArray arrayWithObjects:@"title", @"code", nil]]];
        [arrayActionsMessages addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"Page numéro...", @"chooseTopicPage", nil] forKeys:[NSArray arrayWithObjects:@"title", @"code", nil]]];
        [arrayActionsMessages addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"Copier le lien", @"copyLinkAction", nil] forKeys:[NSArray arrayWithObjects:@"title", @"code", nil]]];
        
        self.topicActionAlert = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        
        for( NSDictionary *dico in arrayActionsMessages) {
            [self.topicActionAlert addAction:[UIAlertAction actionWithTitle:[dico valueForKey:@"title"] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
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
                
        if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone) {
            [self.topicActionAlert addAction:[UIAlertAction actionWithTitle:@"Annuler" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
                [self dismissViewControllerAnimated:YES completion:nil];
            }]];
        } else {
            CGPoint pointLocation = [longPressRecognizer locationInView:self.view];
            CGRect origFrame = CGRectMake( pointLocation.x, pointLocation.y, 1, 1);
            self.topicActionAlert.popoverPresentationController.sourceView = self.view;
            self.topicActionAlert.popoverPresentationController.sourceRect = origFrame;
            self.topicActionAlert.popoverPresentationController.backgroundColor = [ThemeColors alertBackgroundColor:[[ThemeManager sharedManager] theme]];
        }
        
        [self presentViewController:self.topicActionAlert animated:YES completion:nil];
        [[ThemeManager sharedManager] applyThemeToAlertController:self.topicActionAlert];
        
    }
}

-(void)lastPageAction {
    Topic* topic = [self.arrayData objectAtIndex:self.pressedIndexPath.row];
    self.messagesTableViewController = [[MessagesTableViewController alloc] init];
    self.messagesTableViewController.currentUrl = topic.aURLOfLastPage;
    self.messagesTableViewController.topicName = topic.aTitle;
    self.messagesTableViewController.isViewed = topic.isViewed;
    
    [self pushTopic];
}

-(void)firstPageAction {
    Topic* topic = [self.arrayData objectAtIndex:self.pressedIndexPath.row];
    self.messagesTableViewController = [[MessagesTableViewController alloc] init];
    self.messagesTableViewController.currentUrl = topic.aURL;
    self.messagesTableViewController.topicName = topic.aTitle;
    self.messagesTableViewController.isViewed = topic.isViewed;
    
    [self pushTopic];
}


-(void)reset
{
	[super reset];

	//[self.topicsTableView setHidden:YES];
	//[self.maintenanceView setHidden:YES];	
	//[self.loadingView setHidden:YES];	
	

    [self statusBarButton:kNewTopic enable:NO];
}

- (void)parseTopicsListResult:(NSData *)contentData {
    [super parseTopicsListResult:contentData];
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

-(void)statusBarButton:(BARBTNTYPE)type enable:(bool)enable {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    NSInteger vos_sujets = [defaults integerForKey:@"main_gaucheWIP"];

    if (([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad && [self respondsToSelector:@selector(traitCollection)] && [HFRplusAppDelegate sharedAppDelegate].window.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact) ||
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
        if (([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad && [self respondsToSelector:@selector(traitCollection)] && [HFRplusAppDelegate sharedAppDelegate].window.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact) ||
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
    
    
    
    
    
    if (([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad && [self respondsToSelector:@selector(traitCollection)] && [HFRplusAppDelegate sharedAppDelegate].window.traitCollection.horizontalSizeClass == UIUserInterfaceSizeClassCompact) ||
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
