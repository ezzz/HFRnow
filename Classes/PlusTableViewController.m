//
//  PlusTableViewController.m
//  SuperHFRplus
//
//  Created by ezzz on 26/01/2019.
//

#import <Foundation/Foundation.h>
#import "PlusTableViewController.h"
#import "PlusSettingsViewController.h"
#import "CompteViewController.h"
#import "CreditsViewController.h"
#import "BookmarksTableViewController.h"
#import "AQTableViewController.h"
#import "PlusCellView.h"
#import "ThemeColors.h"
#import "ThemeManager.h"

@implementation PlusTableViewController;
@synthesize plusTableView, iAQBadgeNumer, settingsViewController, compteViewController, aqTableViewController, bookmarksTableViewController,  creditsViewController, detailNavigationViewController;
;


- (id)init {
    self = [super init];
    if (self) {
    }
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    UINib *nib = [UINib nibWithNibName:@"PlusCellView" bundle:nil];
    [self.plusTableView registerNib:nib forCellReuseIdentifier:@"PlusCellId"];

    self.title = @"Plus";
    self.navigationController.navigationBar.translucent = NO;
    self.plusTableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    
    self.compteViewController = [[CompteViewController alloc] initWithNibName:@"CompteViewController" bundle:nil];
    self.searchViewController = [[TopicsSearchViewController alloc] init];
    self.searchViewController.currentCat = @"13"; // Discussions
    self.settingsViewController = [[PlusSettingsViewController alloc] initWithNibName:@"SettingsView" bundle:nil];
    self.aqTableViewController = [[AQTableViewController alloc] initWithNibName:@"AQTableView" bundle:nil];
    self.creditsViewController = [[CreditsViewController alloc] initWithNibName:@"CreditsViewController" bundle:nil filename:@"credits"];
    self.charteViewController = [[CreditsViewController alloc] initWithNibName:@"CreditsViewController" bundle:nil filename:@"charte"];
    self.bookmarksTableViewController = [[BookmarksTableViewController alloc] initWithNibName:@"BookmarksTableView" bundle:nil];

    iAQBadgeNumer = 0;
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    { // iPad
        
        [self.detailNavigationViewController setViewControllers:[NSMutableArray arrayWithObjects:self.compteViewController, nil] animated:YES];
        NSIndexPath *indexPath = [NSIndexPath indexPathForRow:0 inSection:0];
        [self.plusTableView selectRowAtIndexPath:indexPath animated:YES scrollPosition:UITableViewScrollPositionNone];
    }
}

- (void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    self.view.backgroundColor = self.plusTableView.backgroundColor = [ThemeColors greyBackgroundColor];
    self.plusTableView.separatorColor = [ThemeColors cellBorderColor];
    if (self.plusTableView.indexPathForSelectedRow) {
        [self.plusTableView deselectRowAtIndexPath:self.plusTableView.indexPathForSelectedRow animated:NO];
    }
    [self.aqTableViewController fetchContentForNewAQ];
    
    [self.plusTableView reloadData];
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    
    UIViewController* vc = nil;
    
    switch (indexPath.row) {
        case 0:
            vc = self.compteViewController;
            break;
        case 1:
            vc = self.searchViewController;
            break;
        case 2:
            vc = self.bookmarksTableViewController;
            break;
        case 3:
            vc = self.aqTableViewController;
            break;
        case 4:
            vc = self.settingsViewController;
            break;
        case 5:
            vc = self.creditsViewController;
            break;
        case 6:
            vc = self.charteViewController;
            break;
        case 7:
            if([MFMailComposeViewController canSendMail]) {
                MFMailComposeViewController *mailCont = [[MFMailComposeViewController alloc] init];
                mailCont.mailComposeDelegate = self;
                [mailCont setSubject:@"Demande de suppression de compte"];
                [mailCont setToRecipients:[NSArray arrayWithObject:@"marc@hardware.fr"]];
                [mailCont setMessageBody:@"Monsieur/Madame,\n\nJe vous écris pour vous demander de supprimer mon compte sur votre forum Hardware.fr. Je ne l'utilise plus et je préfère ne plus être membre de ce forum.\n\nSi vous avez besoin de plus d'informations pour traiter ma demande, veuillez me contacter à l'adresse email associée à mon compte.\n\nMerci d'avance pour votre aide.\n\nCordialement" isHTML:NO];
                [self presentViewController:mailCont animated:YES completion:nil];
            }
            break;
            
    }
    
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPad)
    { // iPad
        if (vc && self.detailNavigationViewController)
        {
            [self.detailNavigationViewController setViewControllers:[NSMutableArray arrayWithObjects:vc, nil] animated:YES];
        }
    }
    else if (vc) { //iPhone
        [self.navigationController pushViewController:vc animated:YES];
    }
}


- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return @"Titre à supprimer";
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return 7;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    PlusCellView *cell = [tableView dequeueReusableCellWithIdentifier:@"PlusCellId"];
    switch (indexPath.row) {
        case 0:
            cell.titleLabel.text = @"Compte(s)";
            cell.titleImage.image = [UIImage imageNamed:@"CircledUserMaleFilled-40"];
            cell.badgeLabel.text = @"";
            cell.badgeLabel.backgroundColor = [UIColor clearColor];
            break;
        case 1:
            cell.titleLabel.text = @"Rechercher sur le forum";
            cell.titleImage.image = [UIImage imageNamed:@"06-magnify"];
            cell.badgeLabel.text = @"";
            cell.badgeLabel.backgroundColor = [UIColor clearColor];
            break;
        case 2:
            cell.titleLabel.text = @"Bookmarks";
            cell.titleImage.image = [UIImage imageNamed:@"08-pin"];
            cell.badgeLabel.text = @"";
            cell.badgeLabel.backgroundColor = [UIColor clearColor];
            break;
        case 3:
            cell.titleLabel.text = @"Alertes Qualitay";
            cell.titleImage.image = [UIImage imageNamed:@"08-chat"];
            cell.badgeLabel.clipsToBounds = YES;
            cell.badgeLabel.layer.cornerRadius = 20 * 1.2 / 2;
            if (iAQBadgeNumer > 0) {
                cell.badgeLabel.backgroundColor =  [ThemeColors tintColor];
                cell.badgeLabel.textColor = [UIColor whiteColor];
                cell.badgeLabel.text = [NSString stringWithFormat:@"%d", iAQBadgeNumer];
            } else {
                cell.badgeLabel.backgroundColor = [UIColor clearColor];
                cell.badgeLabel.textColor = [UIColor clearColor];
                cell.badgeLabel.text = @"";
            }
            break;
        case 4:
            cell.titleLabel.text = @"Réglages";
            cell.titleImage.image = [UIImage imageNamed:@"20-gear2"];
            cell.badgeLabel.text = @"";
            cell.badgeLabel.backgroundColor = [UIColor clearColor];
            break;
        case 5:
            cell.titleLabel.text = @"Crédits";
            cell.titleImage.image = [UIImage imageNamed:@"AboutFilled-25"];
            cell.badgeLabel.text = @"";
            cell.badgeLabel.backgroundColor = [UIColor clearColor];
            break;
        case 6:
            cell.titleLabel.text = @"Charte du forum";
            cell.titleImage.image = [UIImage imageNamed:@"sign-25"];
            cell.badgeLabel.text = @"";
            cell.badgeLabel.backgroundColor = [UIColor clearColor];
            break;
        case 7:
            cell.titleLabel.text = @"Supprimer mon compte";
            cell.titleImage.image = [UIImage imageNamed:@"delete-25"];
            cell.badgeLabel.text = @"";
            cell.badgeLabel.backgroundColor = [UIColor clearColor];
            break;
    }
    
    cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    [[ThemeManager sharedManager] applyThemeToCell:cell];

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 60;
}

- (void)mailComposeController:(MFMailComposeViewController*)controller didFinishWithResult:(MFMailComposeResult)result error:(NSError*)error {
    [self dismissViewControllerAnimated:YES completion:nil];
}

@end


