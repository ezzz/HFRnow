//
//  SmileyCodeTableViewController.m
//  SuperHFRplus
//
//  Created by ezzz on 06/12/2020.
//

#import <Foundation/Foundation.h>
#import "SmileyCodeTableViewController.h"
#import "SmileyCodeCellView.h"
#import "ThemeColors.h"
#import "ThemeManager.h"
#import "ASIHTTPRequest.h"
#import "HTMLParser.h"
#import "HTMLNode.h"

@implementation SmileyCodeTableViewController;
@synthesize codeListTableView, arrCodeList, sSmileyName, loadingView;
;


- (id)init {
    self = [super init];
    if (self) {
    }
    
    return self;
}

- (void)viewDidLoad {
    [super viewDidLoad];

    UINib *nib = [UINib nibWithNibName:@"SmileyCodeCellView" bundle:nil];
    [self.codeListTableView registerNib:nib forCellReuseIdentifier:@"SmileyCodeCellId"];

    self.title = sSmileyName;
    self.navigationController.navigationBar.translucent = NO;
    self.codeListTableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
}

- (void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    self.view.backgroundColor = self.codeListTableView.backgroundColor = [ThemeColors greyBackgroundColor];
    self.codeListTableView.separatorColor = [ThemeColors cellBorderColor];
    /*if (self.codeListTableView.indexPathForSelectedRow) {
        [self.codeListTableView deselectRowAtIndexPath:self.plusTableView.indexPathForSelectedRow animated:NO];
    }*/
    [self requestSmileyCode];
}

/*
- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return @"Titre à supprimer";
}*/

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 1;
}
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.arrCodeList.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    SmileyCodeCellView *cell = [tableView dequeueReusableCellWithIdentifier:@"SmileyCodeCellId"];
    cell.titleLabel.text = [self.arrCodeList objectAtIndex:indexPath.row];
            
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
    return 45;
}

- (void)requestSmileyCode
{
    //Url wiki details : https://forum.hardware.fr/wikismilies.php?config=hfr.inc&detail=%5B%3Aezzz%5D
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"https://forum.hardware.fr/wikismilies.php?config=hfr.inc&detail=%@", [self.sSmileyName stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLHostAllowedCharacterSet]]]];
    ASIHTTPRequest* request = [ASIHTTPRequest requestWithURL:url];
    [request setShouldRedirect:NO];
    [request setDelegate:self];
    request.timeOutSeconds = 2;
    [request setDidFinishSelector:@selector(requestSmileyComplete:)];
    [request setDidFailSelector:@selector(requestSmileyFailed:)];
    [request startAsynchronous];
    [self.loadingView setHidden:NO];
}

- (void)requestSmileyComplete:(ASIHTTPRequest *)request
{
    NSString* content = [request responseString];
    self.arrCodeList = [[NSMutableArray alloc] init];
    if (content) {
        @try {
            NSError *error;
            //NSLog(@"\n----------------------------------------------------\n%@\n----------------------------------------------------", content);
            HTMLParser *myParser = [[HTMLParser alloc] initWithString:content error:&error];
            HTMLNode * bodyNode = [myParser body]; //Find the body tag
            HTMLNode *inputNode = [bodyNode findChildWithAttribute:@"name" matchingName:@"keywords0" allowPartial:NO];
            NSString* text = [inputNode getAttributeNamed:@"value"];
            NSLog(@"Lol: %@", text);
            self.arrCodeList = [[text componentsSeparatedByString:@" "] copy];
            [self.loadingView setHidden:YES];
        }
        @catch (NSException * e) {
            NSLog(@"Exception: %@", e);
        }
        @finally {}
    }
    [self.codeListTableView reloadData];
    [self.loadingView setHidden:YES];
}

- (void)requestSmileyFailed:(ASIHTTPRequest *)request
{
}

@end


