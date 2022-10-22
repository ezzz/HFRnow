//
//  DeleteMessageViewController.m
//  HFRplus
//
//  Created by FLK on 04/09/2015.
//
//

#import "DeleteMessageViewController.h"

@interface DeleteMessageViewController ()

@end

@implementation DeleteMessageViewController

- (void)viewDidLoad {
    //self.navigationItem.prompt = @"Editer";
    [super viewDidLoad];
    
    self.title = @"Supprimer ?";
    //[[self.navBar.items objectAtIndex:2] setTitle:self.title];
    
    //Bouton Envoyer
    [self.navigationItem.rightBarButtonItem setTitle:@"Oui"];
    [self.navigationItem.rightBarButtonItem setEnabled:YES];
    
    [self.segmentControlerPage setEnabled:NO];
    [self.segmentControler     setEnabled:NO];
    [self.segmentControlerPage setEnabled:NO];
    [self.segmentControlerPage setEnabled:NO];
    [self.textViewPostContent setEditable:NO];
    [self.textViewPostContent setAlpha:0.6];
    if ([self.textViewPostContent respondsToSelector:@selector(setSelectable:)]) {
        [self.textViewPostContent setSelectable:NO];
    }
    else {
        [self.textViewPostContent setUserInteractionEnabled:NO];
    }

    
}

-(bool)isDeleteMode {
    return YES;
}
@end
