//
//  ListTableViewController.m
//  SuperHFRplus
//
//  Created by ezzz on 12/07/2019.
//

#import "HFRplusAppDelegate.h"
#import "ListTableViewController.h"
#import "BlackList.h"
#import "InsetLabel.h"
#import "ThemeColors.h"
#import "ThemeManager.h"
#import "Constants.h"

@interface ListTableViewController ()

@end

@implementation ListTableViewController
@synthesize listDict;

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {
    if ((self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])) {
        self.listDict = [[NSMutableArray alloc] init];
    }
    return self;
}

-(void)viewWillAppear:(BOOL)animated {
    NSLog(@"vwa");
    [super viewWillAppear:animated];
    self.view.backgroundColor = [ThemeColors greyBackgroundColor:[[ThemeManager sharedManager] theme]];
    [self reloadData];
}

- (void)reloadData {
}

- (void)viewDidLoad {
    [super viewDidLoad];
    
    // Uncomment the following line to preserve selection between presentations.
    // self.clearsSelectionOnViewWillAppear = NO;
    
    // Uncomment the following line to display an Edit button in the navigation bar for this view controller.
    //self.navigationItem.rightBarButtonItem = self.editButtonItem;
    
    self.edgesForExtendedLayout = UIRectEdgeNone;
    [self hideEmptySeparators];
    
    // Mettre à jour l'icône du bouton
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithTitle:@"Ajouter"
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(addToList)];
}

- (void)didReceiveMemoryWarning {
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)addToList {
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Ajouter à la liste"
                                                                   message:nil
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    
    [alert addTextFieldWithConfigurationHandler:^(UITextField * _Nonnull textField) {
        textField.placeholder = [NSString stringWithFormat:@"pseudo"];
        textField.textAlignment = NSTextAlignmentCenter;
        [textField addTarget:self action:@selector(textFieldDidChange:) forControlEvents:UIControlEventEditingChanged];
        textField.keyboardAppearance = UIKeyboardAppearanceDefault;
        //textField.keyboardType = UIKey;
        textField.delegate = self;
        [[ThemeManager sharedManager] applyThemeToTextField:textField];
        textField.keyboardAppearance = [ThemeColors keyboardAppearance:[[ThemeManager sharedManager] theme]];
    }];
    
    UIAlertAction* cancelAction = [UIAlertAction actionWithTitle:@"Annuler" style:UIAlertActionStyleCancel
                                                         handler:^(UIAlertAction * action) {
                                                         }];
    [alert addAction:cancelAction];
    
    
    UIAlertAction* defaultAction = [UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault
                                                          handler:^(UIAlertAction * action) {
                                                                [self addPseudoToList: [alert.textFields[0] text]];
                                                          }];
    
    [alert addAction:defaultAction];
    [self presentViewController:alert animated:YES completion:nil];
    for (UIView* textfield in alert.textFields) {
        UIView *container = textfield.superview;
        UIView *effectView = container.superview.subviews[0];
        
        if (effectView && [effectView class] == [UIVisualEffectView class]){
            container.backgroundColor = [UIColor clearColor];
            [effectView removeFromSuperview];
        }
    }

    [[ThemeManager sharedManager] applyThemeToAlertController:alert];
}

- (void)textFieldDidChange:(id)sender {
    //NSLog(@"textFieldDidChange %d %@", [[(UITextField *)sender text] intValue], sender);
    // Rien pour le moment
}

- (void)addPseudoToList:(NSString*)sPseudo {
}

#pragma mark - Table view data source

- (NSTextAttachment *)iconForList {
    // creates a text attachment with an image
    NSTextAttachment *attachment = [[NSTextAttachment alloc] init];
    attachment.image = [ThemeColors thorHammer:[[ThemeManager sharedManager] theme]];
    return attachment;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    
    if (self.listDict.count) {
        self.tableView.backgroundView = nil;
        self.tableView.separatorStyle = UITableViewCellSeparatorStyleSingleLine;
        
        return 1;
    }
    else {
        // Display a message when the table is empty
        InsetLabel *messageLabel = [[InsetLabel alloc] initWithFrame:CGRectMake(0, 0, self.view.bounds.size.width, self.view.bounds.size.height)];
        
        if ([NSTextAttachment class]) {
            NSMutableAttributedString *attributedString = [[NSMutableAttributedString alloc] initWithString:@"Pour ajouter quelqu'un, selectionnez son pseudo, puis "];
            
            
            NSAttributedString *imageAttrString = [NSAttributedString attributedStringWithAttachment:[self iconForList]];
            
            [attributedString appendAttributedString:imageAttrString];
            [attributedString appendAttributedString:[[NSAttributedString alloc] initWithString:@" !"]];
            
            messageLabel.attributedText = attributedString;
        }
        else {
            messageLabel.text = @"Pour ajouter quelqu'un, selectionnez son pseudo dans un sujet.";
            messageLabel.font = [UIFont systemFontOfSize:15.0f];
        }
        
        //messageLabel.textColor = [UIColor blackColor];
        messageLabel.numberOfLines = 0;
        messageLabel.textAlignment = NSTextAlignmentCenter;
        //messageLabel.font = [UIFont systemFontOfSize:15.0f];
        [messageLabel sizeToFit];
        messageLabel.textColor = [ThemeColors cellTextColor:[[ThemeManager sharedManager] theme]];
        if ([messageLabel respondsToSelector:@selector(setTintColor:)]) {
            messageLabel.tintColor = [ThemeColors cellIconColor:[[ThemeManager sharedManager] theme]];
        }
        
        self.tableView.backgroundView = messageLabel;
        self.tableView.separatorStyle = UITableViewCellSeparatorStyleNone;
    }
    
    return 0;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    NSLog(@"self.listDict.count %lu", (unsigned long)self.listDict.count);
    return self.listDict.count;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    static NSString *CellIdentifier = @"CellBL";
    
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:CellIdentifier];
    if (!cell)
    {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:CellIdentifier];
        
        cell.accessoryType = UITableViewCellAccessoryNone;
    }
    
    cell.textLabel.text = [[self.listDict objectAtIndex:indexPath.row] valueForKey:@"word"];
    cell.detailTextLabel.text = [[self.listDict objectAtIndex:indexPath.row] valueForKey:@"mode"];
    
    
    [[ThemeManager sharedManager] applyThemeToCell:cell];
    
    return cell;
}


#pragma mark - Table view delegate
// In a xib-based application, navigation from a table can be handled in -tableView:didSelectRowAtIndexPath:
- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    
    [tableView deselectRowAtIndexPath:indexPath animated:YES];
}

- (void)dealloc {
    [self viewDidUnload];
}

@end
