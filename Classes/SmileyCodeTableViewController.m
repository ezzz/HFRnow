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
    //self.codeListTableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
    self.codeListTableView.contentInset = UIEdgeInsetsMake(0, 0, 0, 0);
}

- (void) viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    
    self.view.backgroundColor = self.codeListTableView.backgroundColor = [ThemeColors greyBackgroundColor];
    self.codeListTableView.separatorColor = [ThemeColors cellBorderColor];
    /*if (self.codeListTableView.indexPathForSelectedRow) {
        [self.codeListTableView deselectRowAtIndexPath:self.plusTableView.indexPathForSelectedRow animated:NO];
    }*/
    [self.loadingView setHidden:YES];
    [self.codeListTableView reloadData];
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
            
    cell.accessoryType = UITableViewCellAccessoryNone;

    [[ThemeManager sharedManager] applyThemeToCell:cell];

    cell.selectionStyle = UITableViewCellSelectionStyleNone;

    return cell;
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    return 0;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    return 45;
}



@end


