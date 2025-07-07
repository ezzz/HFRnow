//
//  HFRSearchViewController.m
//  HFRplus
//
//  Created by FLK on 04/11/10.
//

#import "HFRplusAppDelegate.h"
#import "TopicsSearchViewController.h"
#import "ASIFormDataRequest.h"
#import "HTMLParser.h"
#import "RegexKitLite.h"
#import "TopicSearchCellView.h"
#import "MessagesTableViewController.h"
#import "RangeOfCharacters.h"
#import "HFRplusAppDelegate.h"
#import "ASIHTTPRequest+Tools.h"
#import "ThemeManager.h"
#import "ThemeColors.h"
#import "Forum.h"

#define TIME_OUT_INTERVAL_SEARCH 15

@implementation TopicsSearchViewController

#pragma mark - ViewController Methods

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = [NSString stringWithFormat:@"Recherche"]; //, self.forumName];
    
    // 0. Container de l'en-tête -----
    self.searchHeaderView = [[UIView alloc] init];
    self.searchHeaderView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.searchHeaderView];
    
    // 1. Ajouter la SearchBar
    self.textSearchBar = [[UISearchBar alloc] init]; //initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 44)];
    self.textSearchBar.placeholder = @"Rechercher";
    self.textSearchBar.delegate = self;
    self.textSearchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    if ([self.textSearchBar respondsToSelector:@selector(setSearchBarStyle:)]) {
        self.textSearchBar.searchBarStyle = UISearchBarStyleMinimal;
    }
    
    self.textSearchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.searchHeaderView addSubview:self.textSearchBar];

    // 2. Ajouter le SegmentedControl juste en dessous
    //optionSearchTypeSegmentedControl, optionSearchInSegmentedControl, optionSearchFromSegmentedControl;
    // Cat Discussions par defaut
    if ([[NSUserDefaults standardUserDefaults] objectForKey:@"recherche_categorie"] == nil) {
        [[NSUserDefaults standardUserDefaults] setObject:@"13" forKey:@"recherche_categorie"];
    }

    NSArray *items1 = @[@"Tous les mots", @"Au moins un mot", @"Avancé"];
    self.optionSearchTypeSegmentedControl = [[UISegmentedControl alloc] initWithItems:items1];
    self.optionSearchTypeSegmentedControl.selectedSegmentIndex = 0;
    [self.optionSearchTypeSegmentedControl addTarget:self action:@selector(segmentedControlChanged:) forControlEvents:UIControlEventValueChanged];
    self.optionSearchTypeSegmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.searchHeaderView addSubview:self.optionSearchTypeSegmentedControl];

    NSArray *items2 = @[@"Titre et contenu", @"Titre", @"Contenu"];
    self.optionSearchInSegmentedControl = [[UISegmentedControl alloc] initWithItems:items2];
    self.optionSearchInSegmentedControl.selectedSegmentIndex = 0;
    [self.optionSearchInSegmentedControl addTarget:self action:@selector(segmentedControlChanged:) forControlEvents:UIControlEventValueChanged];
    self.optionSearchInSegmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.searchHeaderView addSubview:self.optionSearchInSegmentedControl];

    NSArray *items3 = @[@"Début", @"5 ans", @"1 an"];
    self.optionSearchFromSegmentedControl = [[UISegmentedControl alloc] initWithItems:items3];
    self.optionSearchFromSegmentedControl.selectedSegmentIndex = 0;
    [self.optionSearchFromSegmentedControl addTarget:self action:@selector(segmentedControlChanged:) forControlEvents:UIControlEventValueChanged];
    self.optionSearchFromSegmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.searchHeaderView addSubview:self.optionSearchFromSegmentedControl];
    
    NSString *directory = [NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES) lastObject];
    NSString *forumsCache = [[NSString alloc] initWithString:[directory stringByAppendingPathComponent:FORUMS_CACHE_FILE]];
    NSFileManager *fileManager = [[NSFileManager alloc] init];
    NSMutableArray* arrayListCategories = [[NSMutableArray alloc] init];
    if ([fileManager fileExistsAtPath:forumsCache]) {
        NSData *savedData = [NSData dataWithContentsOfFile:forumsCache];
        arrayListCategories = [NSKeyedUnarchiver unarchiveObjectWithData:savedData];
    }

    NSMutableArray<UIAction *> *childrenList = [[NSMutableArray alloc] init];
    NSString* sCurrentCat = @"";
    self.currentCat = [[NSUserDefaults standardUserDefaults] stringForKey:@"recherche_categorie"];
    for (Forum *aForum in arrayListCategories) {
        NSString *stringValue = [@([aForum getHFRID]) stringValue];
        NSLog(@"SEARCH comparing cat %@ to %@ ID %@", self.currentCat, aForum.aURL, stringValue);
        if ([self.currentCat isEqualToString:[@([aForum getHFRID]) stringValue]]) {
            sCurrentCat = aForum.aTitle;
            NSLog(@"SEARCH FOUND when comparing cat %@ to %@", self.currentCat, aForum.aID);
        }
        UIAction *option = [UIAction actionWithTitle:aForum.aTitle image:nil identifier:nil handler:^(__kindof UIAction * _Nonnull action) {
            NSLog(@"%@ sélectionnée ID %@", aForum.aTitle, [@([aForum getHFRID]) stringValue]);
            self.currentCat = [@([aForum getHFRID]) stringValue];
            [[NSUserDefaults standardUserDefaults] setObject:self.currentCat forKey:@"recherche_categorie"];
            [self.optionSearchCategoryButton setTitle:aForum.aTitle forState:UIControlStateNormal];
        }];
        [childrenList addObject:option];
    }
    
    self.optionSearchCategoryButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.optionSearchCategoryButton setTitle:sCurrentCat forState:UIControlStateNormal];
    self.optionSearchCategoryButton.showsMenuAsPrimaryAction = YES; // Affiche le menu au clic
    self.optionSearchCategoryButton.menu = [UIMenu menuWithTitle:@"Catégorie" children:childrenList];
    self.optionSearchCategoryButton.translatesAutoresizingMaskIntoConstraints = NO;
    [self.searchHeaderView addSubview:self.optionSearchCategoryButton];
    
    // Créer la vue d’assombrissement
    self.backgroundDimView = [[UIView alloc] init];
    self.backgroundDimView.translatesAutoresizingMaskIntoConstraints = NO;
    self.backgroundDimView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.3]; // ou 0.6, selon l’effet désiré
    self.backgroundDimView.hidden = YES; // masquée par défaut
    self.backgroundDimView.alpha = 0.0;
    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(toggleSearchFields)];
    [self.backgroundDimView addGestureRecognizer:tapRecognizer];
    [self.view addSubview:self.backgroundDimView];
    [self.view bringSubviewToFront:self.searchHeaderView]; // searchHeaderView au-dessus du fond

    
    // Contraintes plein écran
    [NSLayoutConstraint activateConstraints:@[
        [self.backgroundDimView.topAnchor constraintEqualToAnchor:self.view.topAnchor],
        [self.backgroundDimView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor],
        [self.backgroundDimView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.backgroundDimView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor]
    ]];
    
    // Contraintes du container (en haut de l'écran)
    [NSLayoutConstraint activateConstraints:@[
        [self.searchHeaderView.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor],
        [self.searchHeaderView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.searchHeaderView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.searchHeaderView.bottomAnchor constraintEqualToAnchor:self.optionSearchFromSegmentedControl.bottomAnchor constant:20]
    ]];
    
    // Contraintes Auto Layout
    [NSLayoutConstraint activateConstraints:@[
        [self.textSearchBar.topAnchor constraintEqualToAnchor:self.searchHeaderView.topAnchor constant:6],
        [self.textSearchBar.leadingAnchor constraintEqualToAnchor:self.searchHeaderView.leadingAnchor],
        [self.textSearchBar.trailingAnchor constraintEqualToAnchor:self.searchHeaderView.trailingAnchor],
        [self.textSearchBar.heightAnchor constraintEqualToConstant:44]
    ]];
    
    // Contraintes Auto Layout
    /*
    [NSLayoutConstraint activateConstraints:@[
        [self.optionSearchCategoryLabel.topAnchor constraintEqualToAnchor:self.textSearchBar.bottomAnchor constant:16],
        [self.optionSearchCategoryLabel.leadingAnchor constraintEqualToAnchor:self.searchHeaderView.leadingAnchor constant:24],
        [self.optionSearchCategoryLabel.widthAnchor constraintEqualToAnchor:self.searchHeaderView.widthAnchor multiplier:0.35 constant:-24], // moitié moins les marges
        [self.optionSearchCategoryLabel.heightAnchor constraintEqualToConstant:30],

        [self.optionSearchCategoryButton.centerYAnchor constraintEqualToAnchor:self.optionSearchCategoryLabel.centerYAnchor],
        [self.optionSearchCategoryButton.leadingAnchor constraintEqualToAnchor:self.optionSearchCategoryLabel.trailingAnchor constant:8],
        [self.optionSearchCategoryButton.trailingAnchor constraintEqualToAnchor:self.searchHeaderView.trailingAnchor constant:-16],
        [self.optionSearchCategoryButton.heightAnchor constraintEqualToConstant:30]
    ]];

    */
    [NSLayoutConstraint activateConstraints:@[
        [self.optionSearchCategoryButton.topAnchor constraintEqualToAnchor:self.textSearchBar.bottomAnchor constant:16],
        [self.optionSearchCategoryButton.leadingAnchor constraintEqualToAnchor:self.searchHeaderView.leadingAnchor constant:16],
        [self.optionSearchCategoryButton.trailingAnchor constraintEqualToAnchor:self.searchHeaderView.trailingAnchor constant:-16],
        [self.optionSearchCategoryButton.heightAnchor constraintEqualToConstant:30]
    ]];

    
    [NSLayoutConstraint activateConstraints:@[
        [self.optionSearchTypeSegmentedControl.topAnchor constraintEqualToAnchor:self.optionSearchCategoryButton.bottomAnchor constant:16],
        [self.optionSearchTypeSegmentedControl.leadingAnchor constraintEqualToAnchor:self.searchHeaderView.leadingAnchor constant:16],
        [self.optionSearchTypeSegmentedControl.trailingAnchor constraintEqualToAnchor:self.searchHeaderView.trailingAnchor constant:-16],
        [self.optionSearchTypeSegmentedControl.heightAnchor constraintEqualToConstant:30]
    ]];

    [NSLayoutConstraint activateConstraints:@[
        [self.optionSearchInSegmentedControl.topAnchor constraintEqualToAnchor:self.optionSearchTypeSegmentedControl.bottomAnchor constant:16],
        [self.optionSearchInSegmentedControl.leadingAnchor constraintEqualToAnchor:self.searchHeaderView.leadingAnchor constant:16],
        [self.optionSearchInSegmentedControl.trailingAnchor constraintEqualToAnchor:self.searchHeaderView.trailingAnchor constant:-16],
        [self.optionSearchInSegmentedControl.heightAnchor constraintEqualToConstant:30]
    ]];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.optionSearchFromSegmentedControl.topAnchor constraintEqualToAnchor:self.optionSearchInSegmentedControl.bottomAnchor constant:16],
        [self.optionSearchFromSegmentedControl.leadingAnchor constraintEqualToAnchor:self.searchHeaderView.leadingAnchor constant:16],
        [self.optionSearchFromSegmentedControl.trailingAnchor constraintEqualToAnchor:self.searchHeaderView.trailingAnchor constant:-16],
        [self.optionSearchFromSegmentedControl.heightAnchor constraintEqualToConstant:30]
    ]];
    

    // 3. TableView – pour historique
    /*
    self.historicTableView = [[UITableView alloc] init];
    self.historicTableView.dataSource = self;
    self.historicTableView.delegate = self;
    
    self.historicTableView.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.historicTableView];

    [NSLayoutConstraint activateConstraints:@[
        [self.historicTableView.topAnchor constraintEqualToAnchor:self.optionSearchFromSegmentedControl.bottomAnchor constant:8],
        [self.historicTableView.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.historicTableView.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.historicTableView.bottomAnchor constraintEqualToAnchor:self.view.bottomAnchor]
    ]];*/

    // Loading view
    self.loadingView = [[UIView alloc] init];
    self.loadingView.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingView.backgroundColor = [UIColor clearColor];// colorWithAlphaComponent:0.1]; // fond assombri

    [self.view addSubview:self.loadingView];

    [NSLayoutConstraint activateConstraints:@[
        [self.loadingView.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [self.loadingView.centerYAnchor constraintEqualToAnchor:self.view.centerYAnchor],
        [self.loadingView.widthAnchor constraintEqualToConstant:200],
        [self.loadingView.heightAnchor constraintEqualToConstant:60]
    ]];
    


    // ----- Boîte centrée -----
    self.locadingContainerView = [[UIView alloc] init];
    self.locadingContainerView.translatesAutoresizingMaskIntoConstraints = NO;
    self.locadingContainerView.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.8];
    self.locadingContainerView.layer.cornerRadius = 10;
    self.locadingContainerView.clipsToBounds = YES;
    [self.loadingView addSubview:self.locadingContainerView];

    [NSLayoutConstraint activateConstraints:@[
        [self.locadingContainerView.centerXAnchor constraintEqualToAnchor:self.loadingView.centerXAnchor],
        [self.locadingContainerView.centerYAnchor constraintEqualToAnchor:self.loadingView.centerYAnchor],
        [self.locadingContainerView.widthAnchor constraintEqualToConstant:200],
        [self.locadingContainerView.heightAnchor constraintEqualToConstant:60]
    ]];
    
    // ----- Spinner -----
    self.activityIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    self.activityIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    [self.activityIndicator startAnimating];
    [self.locadingContainerView addSubview:self.activityIndicator];

    // ----- Label -----
    self.loadingLabel = [[UILabel alloc] init];
    self.loadingLabel.translatesAutoresizingMaskIntoConstraints = NO;
    self.loadingLabel.text = @"Chargement...";
    self.loadingLabel.font = [UIFont fontWithName:@"Helvetica-Bold" size:14];
    [self.locadingContainerView addSubview:self.loadingLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.activityIndicator.centerYAnchor constraintEqualToAnchor:self.locadingContainerView.centerYAnchor],
        [self.activityIndicator.leadingAnchor constraintEqualToAnchor:self.locadingContainerView.leadingAnchor constant:20],

        [self.loadingLabel.centerYAnchor constraintEqualToAnchor:self.locadingContainerView.centerYAnchor],
        [self.loadingLabel.leadingAnchor constraintEqualToAnchor:self.activityIndicator.trailingAnchor constant:12],
        [self.loadingLabel.trailingAnchor constraintEqualToAnchor:self.locadingContainerView.trailingAnchor constant:-20]
    ]];
    
    // Autres paramètres
    self.maintenanceView.hidden = YES; // cachée par défaut
    self.topicsTableView.hidden = NO; // Non cachée par défaut (toujours en arrière plan)
    self.loadingView.hidden = YES; // cachée par défaut
    
    /*self.disableViewOverlay = [[UIView alloc] initWithFrame:CGRectMake(0.0f, 0.0f, 1000.0f, 1000.0f)];
    self.disableViewOverlay.backgroundColor = [UIColor blackColor];
    self.disableViewOverlay.alpha = 0;
    self.disableViewOverlay.autoresizingMask = (UIViewAutoresizingFlexibleWidth);
    tapRecognizer = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    [self.disableViewOverlay addGestureRecognizer:tapRecognizer];*/
    
    [self.maintenanceView setText:@"Aucun résultat"];
    
    NSLog(@"backgroundDimView %@", self.backgroundDimView);
    NSLog(@"loadingView %@", self.loadingView);
    NSLog(@"locadingContainerView %@", self.locadingContainerView);
    NSLog(@"disableViewOverlay %@", self.disableViewOverlay);
    NSLog(@"maintenanceView %@", self.maintenanceView);

    
    self.arrayData = [[NSMutableArray alloc] init];
    self.arrayNewData = [[NSMutableArray alloc] init];
    
    self.imageForUnselectedRow = [UIImage imageNamed:@"selectedrow"];
    self.imageForSelectedRow = [UIImage imageNamed:@"unselectedrow"];
    self.imageForRedFlag = [UIImage imageNamed:@"Flat-RedFlag-25"];
    self.imageForYellowFlag = [UIImage imageNamed:@"Flat-YellowFlag-25"];
    self.imageForBlueFlag = [UIImage imageNamed:@"Flat-CyanFlag-25"];
        
    [self setSearchFieldsHidden:NO];
}

- (void) viewWillAppear:(BOOL)animated
{
    //[self.navigationController setNavigationBarHidden:YES animated:animated];
    [super viewWillAppear:animated];
    
    Theme theme = [[ThemeManager sharedManager] theme];
    self.view.backgroundColor = self.maintenanceView.backgroundColor = self.topicsTableView.backgroundColor = [ThemeColors greyBackgroundColor:theme];
    self.searchHeaderView.backgroundColor = [ThemeColors toolbarPageBackgroundColor:theme];
    self.optionSearchInSegmentedControl.backgroundColor = self.optionSearchFromSegmentedControl.backgroundColor = self.optionSearchTypeSegmentedControl.backgroundColor = [UIColor systemGray5Color];
    self.textSearchBar.backgroundColor = [ThemeColors toolbarPageBackgroundColor:theme];
    self.optionSearchInSegmentedControl.backgroundColor = [UIColor systemGray5Color];
    self.optionSearchCategoryButton.backgroundColor = [UIColor systemGray5Color];
    [self.optionSearchCategoryButton setTitleColor:[ThemeColors tintColor] forState:UIControlStateNormal];
    
    self.optionSearchCategoryButton.layer.cornerRadius = 6.0;
    
    self.topicsTableView.separatorColor = [ThemeColors cellBorderColor:theme];

    // New
    NSDictionary *selectedAttributes = @{NSForegroundColorAttributeName: [UIColor systemBackgroundColor]};
    [self.optionSearchFromSegmentedControl setTitleTextAttributes:selectedAttributes forState:UIControlStateSelected];
    [self.optionSearchInSegmentedControl setTitleTextAttributes:selectedAttributes forState:UIControlStateSelected];
    [self.optionSearchTypeSegmentedControl setTitleTextAttributes:selectedAttributes forState:UIControlStateSelected];


    self.loadingView.backgroundColor = [[ThemeColors greyBackgroundColor:theme] colorWithAlphaComponent:0.3];
    self.locadingContainerView.backgroundColor = [[ThemeColors greyBackgroundColor:theme] colorWithAlphaComponent:0.6];
    self.loadingLabel.textColor = [ThemeColors cellTextColor:theme];
    self.loadingLabel.shadowColor = nil;
    self.activityIndicator.activityIndicatorViewStyle = [ThemeColors activityIndicatorViewStyle];

    if (self.messagesTableViewController) {
        self.messagesTableViewController = nil;
    }
}

- (void)toggleSearchFields {
    NSLog(@"SEARCH toggle %d %d %d", self.maintenanceView.hidden, self.topicsTableView.hidden, self.loadingView.hidden);
    if (self.maintenanceView.hidden &&
        (self.topicsTableView.hidden || self.arrayData.count == 0) &&
        self.loadingView.hidden) {
        
        [self.textSearchBar endEditing:YES];
        return; // Do nothing when everything else is hidden
    }
    self.searchVisible = !self.searchVisible;
    [self setSearchFieldsHidden:self.searchVisible];
}

- (void)setSearchFieldsHidden:(BOOL)bHidden {
    self.searchVisible = bHidden;
    self.searchHeaderView.hidden = self.searchVisible;
    
    if (bHidden) {
        [self.searchHeaderView endEditing:YES];
    
        // Afficher avec animation
        self.backgroundDimView.alpha = 1;
        self.backgroundDimView.hidden = YES;
        [UIView animateWithDuration:0.25 animations:^{
            self.backgroundDimView.alpha = 0;
        }];
        NSLog(@"tableView interaction: %d", self.topicsTableView.userInteractionEnabled);
    }
    else {
        // Afficher avec animation
        self.backgroundDimView.alpha = 0;
        self.backgroundDimView.hidden = NO;
        [UIView animateWithDuration:0.25 animations:^{
            self.backgroundDimView.alpha = 1;
        }];
   
        // Forcer layout pour que le champ texte soit bien en place
        //[self.searchHeaderView layoutIfNeeded];
    }
    
    /*// Si tu utilises Auto Layout :
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];*/
}

/*
- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    // We don't want to do anything until the user clicks
    // the 'Search' button.
    // If you wanted to display results as the user types
    // you would do that here.
}

- (void)searchBarTextDidBeginEditing:(UISearchBar *)searchBar {
    // searchBarTextDidBeginEditing is called whenever
    // focus is given to the UISearchBar
    // call our activate method so that we can do some
    // additional things when the UISearchBar shows.
    [self searchBar:searchBar activate:YES];
    [searchBar setShowsCancelButton:NO animated:NO];
}

- (void)searchBarTextDidEndEditing:(UISearchBar *)searchBar {
    // searchBarTextDidEndEditing is fired whenever the
    // UISearchBar loses focus
    // We don't need to do anything here.
    [searchBar setShowsCancelButton:NO animated:NO];
}

-(void)handleTap:(id)sender{
    [self searchBar:self.textSearchBar activate:NO];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    // Clear the search text
    // Deactivate the UISearchBar
    searchBar.text = @"";
    [self searchBar:searchBar activate:NO];
}*/

// Do the search and show the results in tableview & deactivate the UISearchBar
- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    NSLog(@"SEARCH START !!");
    [self searchBar:searchBar activate:NO];

    self.loadingView.hidden = NO;
    [self.activityIndicator startAnimating];
    
    [self setSearchFieldsHidden:YES];
    self.maintenanceView.hidden = YES;
    self.topicsTableView.hidden = NO;
    
    // Mettre à jour l'icône du bouton
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"xmark"]
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(cancelFetchContent)];

    [self fetchContentForSearch];
}

// We call this when we want to activate/deactivate the UISearchBar
// Depending on active (YES/NO) we disable/enable selection and
// scrolling on the UITableView
// Show/Hide the UISearchBar Cancel button
// Fade the screen In/Out with the disableViewOverlay and
// simple Animations
- (void)searchBar:(UISearchBar *)searchBar activate:(BOOL) active{
    
    self.topicsTableView.allowsSelection = !active;
    self.topicsTableView.scrollEnabled = !active;
    if (!active) {
        //[disableViewOverlay removeFromSuperview];
        [searchBar resignFirstResponder];
    } else {

        /*
        self.disableViewOverlay.alpha = 0;
        [self.view addSubview:self.disableViewOverlay];*/
        
        [UIView beginAnimations:@"FadeIn" context:nil];
        [UIView setAnimationDuration:0.5];
        //self.disableViewOverlay.alpha = 0.6;
        [UIView commitAnimations];
        
        // probably not needed if you have a details view since you
        // will go there on selection
        NSIndexPath *selected = [self.topicsTableView
                                 indexPathForSelectedRow];
        if (selected) {
            [self.topicsTableView deselectRowAtIndexPath:selected
                                             animated:NO];
        }
    }
    [searchBar setShowsCancelButton:active animated:YES];
}

#pragma mark - Data lifecycle - Search request

- (void)createPostString
{
    NSString *searchInput = [self.textSearchBar.text lowercaseString];
    NSArray *bannedWords = [NSArray arrayWithObjects:@"jailbreak", @"cydia", @"pengu", @"apple jb", nil];
    
    for (NSString *word in bannedWords) {
        if ([searchInput rangeOfString:word].location == NSNotFound) {
            //On est bon.
        } else {
            //On est pas bon :o
            searchInput = @"SSBEb24ndCBXYW50IHRvIExpdmUgb24gVGhpcyBQbGFuZXQgQW55bW9yZQ==";
            break;
        }
    }
    
    /* Options de recherche
     
    Type de recherche
    <select name="searchtype">
        <option value="1" selected="selected">Tous les mots</option>
        <option value="2">Au moins un mot</option>
        <option value="0">Recherche avancée</option>
     
     Rechercher dans
     <select name="titre" id="rechercherdans">
        <option value="1">les titres de sujets</option>
        <option value="3" selected="selected">les titres de sujets et le contenu des messages</option>
        <option value="0">le contenu des messages</option>
    
    A partir du
    <select name="daterange" onchange="pouet1(this);">
        <option value="0">postés le</option>
        <option value="1">à partir du</option>
        <option value="2" selected="selected">depuis le début</option>

        <div id="date" style="display:none">
             <input type="text" name="jour" size="2" maxlength="2" value="06"> -
             <input type="text" name="mois" size="2" maxlength="2" value="02"> -
             <input type="text" name="annee" size="4" maxlength="4" value="2025">
    
     OrderSearch
     
     <select name="orderSearch">
        <option value="0" selected="selected">selon la date des messages trouvés</option>
        <option value="1">selon la date des derniers messages du sujet</option>
     */
    
    NSString* sSearchType = @"0";
    if (self.optionSearchTypeSegmentedControl.selectedSegmentIndex == 0) {
        sSearchType = @"1";
    }
    else if (self.optionSearchTypeSegmentedControl.selectedSegmentIndex == 1) {
        sSearchType = @"2";
    }

    // SearchIn - [@"Titre et contenu", @"Titre", @"Contenu"];
    NSString* sSearchIn = @"3"; // Titre et contenu
    if (self.optionSearchInSegmentedControl.selectedSegmentIndex == 1) {
        sSearchIn = @"1"; // Titre seulement
    }
    else if (self.optionSearchInSegmentedControl.selectedSegmentIndex == 2) {
        sSearchIn = @"0"; // Contenu seulement
    }

    // A partir du - @[@"Début", @"5 ans", @"1 an", @"1 mois"];
    NSString* sSearchFrom = @"2"; // Depuis le début
    NSDateComponents *deltaDate = [[NSDateComponents alloc] init];
    if (self.optionSearchFromSegmentedControl.selectedSegmentIndex == 1) {
        sSearchFrom = @"1";
        deltaDate.year = -5;
    }
    else if (self.optionSearchFromSegmentedControl.selectedSegmentIndex == 2) {
        sSearchFrom = @"1";
        deltaDate.year = -1;
    }
    NSLog(@"SEARCH %@", sSearchFrom);
    NSString *dateDepuisLe = @"";
    if ([sSearchFrom isEqualToString:@"1"])
    {
        NSDate *aujourdhui = [NSDate date];
        NSCalendar *calendrier = [NSCalendar currentCalendar];
        NSDate *datePasse = [calendrier dateByAddingComponents:deltaDate toDate:aujourdhui options:0];
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        [formatter setLocale:[[NSLocale alloc] initWithLocaleIdentifier:@"fr_FR"]]; // Locale explicite
        [formatter setDateFormat:@"'&jour='dd'&mois='MM'&annee='yyyy"]; // Les littéraux doivent être entre apostrophes
        dateDepuisLe = [formatter stringFromDate:datePasse];
    }
    NSLog(@"SEARCH dateDepuisLe %@", dateDepuisLe);

    // Paramètres encodés façon x-www-form-urlencoded
    NSString *postString = [NSString stringWithFormat:
                            //@"hash_check=%@&cat=%@&search=%@&resSearch=%@&orderSearch=%@&titre=%@&searchtype=%@&pseud=%@",
                            @"hash_check=%@&cat=%@&search=%@&resSearch=%@&orderSearch=%@&titre=%@&searchtype=%@&pseud=%@&daterange=%@%@",
                            [[HFRplusAppDelegate sharedAppDelegate] hash_check],
                            self.currentCat, // (cat) 13= Discussions
                            [searchInput stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet URLQueryAllowedCharacterSet]],
                            @"200", //(resSearch)
                            @"0",//@(orderSearch) //0-selon la date des messages trouvés</option>
                            sSearchIn, // 0 Messages, 1 Titre, 3-les titres de sujets et le contenu des messages
                            sSearchType,
                            @"",
                            sSearchFrom,
                            dateDepuisLe
                        ];

    NSLog(@"SEARCH Request POST attributes: %@", postString);
    self.dInputPostData = [postString dataUsingEncoding:NSUTF8StringEncoding];
}

- (void)fetchContentForSearch {
    NSLog(@"SEARCH fetchContent");
	
    [self createPostString];
    
    // 1. URL cible
    NSURL *url = [NSURL URLWithString:@"https://forum.hardware.fr/search.php?config=hardwarefr.inc"];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    
    // 3. Headers
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    //[request setValue:@"Mozilla/5.0" forHTTPHeaderField:@"User-Agent"];
    [request setHTTPBody:self.dInputPostData];
    //NSString *postLength = [NSString stringWithFormat:@"%ld",[postData length]];
    //[request setValue:postLength forHTTPHeaderField:@"Content-Length"];
    [request setTimeoutInterval:TIME_OUT_INTERVAL_SEARCH];
        
    // 4. Config de session (inclut gestion SSL si nécessaire)
    // Session & tâche
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyAlways;
    config.HTTPCookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
    NSURLSession *session = [NSURLSession sessionWithConfiguration:config];

    // 5. Envoi async
    NSURLSessionDataTask *task = [session dataTaskWithRequest:request
                                            completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"❌ Erreur réseau : %@", error);
        } else {
            //NSLog(@"✅ Statut HTTP : %ld", (long)[(NSHTTPURLResponse *)response statusCode]);
            //NSLog(@"📦 Taille de la réponse : %lu", (unsigned long)data.length);

            //NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            //NSLog(@"🔍 HTML reçu (début) : %@", [html substringToIndex:MIN(html.length, 2000)]);
            
            /*
            NSUInteger length = html.length;
            NSUInteger blockSize = 1000;
            for (NSUInteger i = 0; i < length; i += blockSize) {
                NSUInteger thisBlockSize = MIN(blockSize, length - i);
                NSString *block = [html substringWithRange:NSMakeRange(i, thisBlockSize)];
                NSLog(@"🧩 Bloc %lu : %@", (unsigned long)(i / blockSize + 1), block);
            }*/
            
            NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSString *redirectURL = [self extractRedirectURLFromHTML:html];
            if (redirectURL) {
                NSLog(@"🔁 Redirection trouvée vers : %@", redirectURL);
                //[self followRedirectToURL2:redirectURL];
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.0 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self followRedirectToURL:redirectURL];
                });
            } else {
                NSLog(@"📄 Pas de redirection détectée.");
                [self setMaintenanceView:@"Pas de redirection"];
            }
        }
        /*HTMLParser * myParser = [[HTMLParser alloc] initWithData:data error:NULL];
        HTMLNode * bodyNode = [myParser body];
        NSLog(@"rawContentsOfNode %@", rawContentsOfNode([bodyNode _node], [myParser _doc]));*/
    }];

    [task resume];
}


- (void)followRedirectToURL:(NSString *)urlString {
    if ([urlString hasPrefix:@"/"]) {
        urlString = [@"https://forum.hardware.fr" stringByAppendingString:urlString];
    }
    self.currentUrl = urlString;
    
    NSURL *url = [NSURL URLWithString:urlString];
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = @"POST";
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    [request setHTTPBody:self.dInputPostData];

    NSURLSession *session = [NSURLSession sharedSession];
    NSURLSessionDataTask *redirectTask = [session dataTaskWithRequest:request
                                                    completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            NSLog(@"❌ Erreur lors de la redirection : %@", error);
            [self setMaintenanceViewWithText:@"Pas de redirection"];
        } else {
            NSLog(@"Statut HTTP redirection : %ld", (long)[(NSHTTPURLResponse *)response statusCode]);
            
            // Parse result
            [self parseTopicsListResult:data];
            
            [self.arrayData removeAllObjects];
            self.arrayData = [NSMutableArray arrayWithArray:self.arrayNewData];
            [self.arrayNewData removeAllObjects];
            
            // Appel de la méthode UI sur le thread principal
            dispatch_async(dispatch_get_main_queue(), ^{
                NSLog(@"How many results:%ld", [self.arrayData count]);

                if ([self.arrayData count] == 0) {
                    [self setMaintenanceViewWithText:@"Aucun résultat"];
                }
                else {
                    //NSLog(@"Show results");
                    [self.maintenanceView setHidden:YES];
                    [self.topicsTableView setHidden:NO];
                    [self.loadingView setHidden:YES];
                    [self.activityIndicator stopAnimating];
                }
                
                // Mettre à jour l'icône du bouton
                // Mettre à jour l'icône du bouton
                self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
                    initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]
                    style:UIBarButtonItemStylePlain
                    target:self
                    action:@selector(toggleSearchFields)];
                
                [self.topicsTableView setContentOffset:CGPointZero animated:YES];
                [self.topicsTableView reloadData];
                            
                [(UISegmentedControl *)[self.navigationItem.titleView.subviews objectAtIndex:0] setUserInteractionEnabled:YES];
                [self cancelFetchContent];
                NSLog(@"SEARCH DONE !!");
            });
        }
    }];
    
    [redirectTask resume];
}


- (NSString *)extractRedirectURLFromHTML:(NSString *)html {
    NSError *error = nil;
    
    // Regex pour détecter toute la balise <meta> avec refresh + URL
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"<meta[^>]*http-equiv=[\"']?refresh[\"']?[^>]*content=[\"']\\d+;\\s*url=([^\"']+)[\"'][^>]*>"
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:&error];
    
    if (error) {
        NSLog(@"❌ Erreur regex : %@", error.localizedDescription);
        [self setMaintenanceViewWithText:@"Erreur regex"];
        return nil;
    }
    
    NSTextCheckingResult *match = [regex firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
    
    if (match && match.numberOfRanges > 1) {
        NSRange fullTagRange = [match rangeAtIndex:0];
        NSString *metaTag = [html substringWithRange:fullTagRange];
        NSLog(@"🔎 Balise <meta> détectée : %@", metaTag);
        
        NSString *redirectURL = [html substringWithRange:[match rangeAtIndex:1]];
        return redirectURL;
    }
    
    NSLog(@"⚠️ Aucune balise <meta refresh> détectée dans le HTML.");
    NSLog(@"html %@", html);
    [self setMaintenanceViewWithText:@"Aucune balise"];
    return nil;
}

- (void)cancelFetchContentSearch
{
    [self.request cancel];
    self.searchVisible = NO;
    NSLog(@"BUTTON magnifyingglass");
    
    // Mettre à jour l'icône du bouton
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(toggleSearchFields)];
    
    [self setSearchFieldsHidden:NO];
    self.loadingView.hidden = YES;
    [self.activityIndicator stopAnimating];
}

// 3. Action lors du changement de sélection
- (void)segmentedControlChanged:(UISegmentedControl *)sender {
    NSInteger selectedIndex = sender.selectedSegmentIndex;
    NSLog(@"Segment sélectionné : %ld", (long)selectedIndex);
    // Filtrage, changement de catégorie, etc.
}

- (void)fetchContent
{
    [self setSearchFieldsHidden:YES];
    self.maintenanceView.hidden = YES;
    self.loadingView.hidden = NO;
    self.topicsTableView.hidden = NO;
    [self.activityIndicator startAnimating];

    [super fetchContent];
    [self fetchContentTrigger];
}

- (void)fetchContentComplete:(ASIHTTPRequest *)theRequest
{
    [super fetchContentComplete:theRequest];
    
    [self setSearchFieldsHidden:YES];
    self.maintenanceView.hidden = YES;
    self.topicsTableView.hidden = NO;
    [self.activityIndicator stopAnimating];
    self.loadingView.hidden = YES;
}

- (void)setMaintenanceViewWithText:(NSString*)sMaintenanceText {
    [self.maintenanceView setText:sMaintenanceText];
    [self.maintenanceView setHidden:NO];
    [self.topicsTableView setHidden:YES];
    [self.loadingView setHidden:YES];
    [self.activityIndicator stopAnimating];
}

#pragma mark - Table view data source

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    NSInteger iSizeTextTopics = [[NSUserDefaults standardUserDefaults] integerForKey:@"size_text_topics"];
    return 36.0f*iSizeTextTopics/100;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    if ([self pageNumber] == 0 || self.arrayData.count == 0) {
        return 0;
    }
    return 1;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    return [NSString stringWithFormat:@"Résultats p.%d", [self pageNumber]]; // [self forumName] is null, dommage...
}


- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (tableView == self.topicsTableView) {
        NSInteger iSizeTextTopics = [[NSUserDefaults standardUserDefaults] integerForKey:@"size_text_topics"];
        Topic *aTopic = [self.arrayData objectAtIndex:indexPath.row];
        if (aTopic.sLastSearchPostContent.length > 0) {
            return 110*iSizeTextTopics/100;
        }
        
        return 60*iSizeTextTopics/100;
    }
    else if (tableView == self.historicTableView) {
        return 45;
    }
    
    return 40; // Should not be used
}


- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    if (tableView == self.topicsTableView) {
        return self.arrayData.count;
    }
    else if (tableView == self.historicTableView){
        return 0;
    }
    
    return 1;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    
    if (tableView == self.topicsTableView) {
        
        static NSString *CellIdentifier = @"TopicSearchCellView";
        TopicSearchCellView *cell = (TopicSearchCellView *)[tableView dequeueReusableCellWithIdentifier:CellIdentifier];
        
        if (cell == nil) {
            [[NSBundle mainBundle] loadNibNamed:@"TopicSearchCellView" owner:self options:nil];
            cell = self.tmpCell;
            cell.accessoryType = UITableViewCellAccessoryNone;
            cell.selectionStyle = UITableViewCellSelectionStyleBlue;
            self.tmpCell = nil;
        }
        
        Topic *aTopic = [self.arrayData objectAtIndex:indexPath.row];
        
        NSInteger iSizeTextTopics = [[NSUserDefaults standardUserDefaults] integerForKey:@"size_text_topics"];
        
        UIFont *font1 = [UIFont boldSystemFontOfSize:13.0f*iSizeTextTopics/100];
        if ([aTopic isViewed]) {
            font1 = [UIFont systemFontOfSize:13.0f*iSizeTextTopics/100];
        }
        NSDictionary *arialDict = [NSDictionary dictionaryWithObject: font1 forKey:NSFontAttributeName];
        NSMutableAttributedString *aAttrString1 = [[NSMutableAttributedString alloc] initWithString:[aTopic aTitle] attributes: arialDict];
        
        UIFont *font2 = [UIFont fontWithName:@"fontello" size:15.0f*iSizeTextTopics/100];
        
        NSMutableAttributedString *finalString = [[NSMutableAttributedString alloc]initWithString:@""];
        
        if (aTopic.isSticky) {
            UIColor *fontsC = [UIColor colorWithHex:@"#e74c3c" alpha:1.0];
            NSDictionary *arialDict2S = [NSDictionary dictionaryWithObjectsAndKeys:font2, NSFontAttributeName, fontsC, NSForegroundColorAttributeName, nil];
            NSMutableAttributedString *aAttrString2S = [[NSMutableAttributedString alloc] initWithString:@" " attributes: arialDict2S];
            
            [finalString appendAttributedString:aAttrString2S];
        }
        
        if (aTopic.isClosed) {
            //            UIColor *fontcC = [UIColor orangeColor];
            UIColor *fontcC = [UIColor colorWithHex:@"#4A4A4A" alpha:1.0];
            
            
            NSDictionary *arialDict2c = [NSDictionary dictionaryWithObjectsAndKeys:font2, NSFontAttributeName, fontcC, NSForegroundColorAttributeName, nil];
            NSMutableAttributedString *aAttrString2C = [[NSMutableAttributedString alloc] initWithString:@" " attributes: arialDict2c];
            
            [finalString appendAttributedString:aAttrString2C];
            //NSLog(@"finalString1 %@", finalString);
        }
        
        [finalString appendAttributedString:aAttrString1];
        
        cell.titleLabel.attributedText = finalString;
        cell.titleLabel.numberOfLines = 2;
        
        cell.contentLabel.text = aTopic.sLastSearchPostContent;
        cell.contentLabel.numberOfLines = 3;
        
        NSString* sPoll = @"";
        if (aTopic.isPoll) {
            sPoll = @" \U00002263";
        }
        if (aTopic.curTopicPage > 0 && aTopic.curTopicPage <= aTopic.maxTopicPage) {
            [cell.msgLabel setText:[NSString stringWithFormat:@"⚑%@ %d / %d", sPoll, aTopic.curTopicPage, aTopic.maxTopicPage]];
        }
        else {
            [cell.msgLabel setText:[NSString stringWithFormat:@"⚑%@ %d", sPoll, aTopic.maxTopicPage]];
        }
        [cell.msgLabel setFont:[UIFont systemFontOfSize:13.0*iSizeTextTopics/100]];

        // Time label
        [cell.timeLabel setText:[NSString stringWithFormat:@"%@ - %@", [aTopic aAuthorOfLastPost], [aTopic aDateOfLastPost]]];
        [cell.timeLabel setFont:[UIFont systemFontOfSize:11.0*iSizeTextTopics/100]];

        //Flag
        if (aTopic.aTypeOfFlag.length > 0) {
            
            UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
            
            CGRect frame = CGRectMake(0.0, 0.0, 45, 50);
            button.frame = frame;    // match the button's size with the image size
            
            if (aTopic.isViewed) {
                [button setBackgroundImage:self.imageForGreyFlag forState:UIControlStateNormal];
                [button setBackgroundImage:self.imageForGreyFlag forState:UIControlStateHighlighted];
            }
            else {
                if([[aTopic aTypeOfFlag] isEqualToString:@"red"]) {
                    [button setBackgroundImage:self.imageForRedFlag forState:UIControlStateNormal];
                    [button setBackgroundImage:self.imageForRedFlag forState:UIControlStateHighlighted];
                }
                else if ([[aTopic aTypeOfFlag] isEqualToString:@"blue"]) {
                    [button setBackgroundImage:self.imageForBlueFlag forState:UIControlStateNormal];
                    [button setBackgroundImage:self.imageForBlueFlag forState:UIControlStateHighlighted];
                }
                else if ([[aTopic aTypeOfFlag] isEqualToString:@"yellow"]) {
                    [button setBackgroundImage:self.imageForYellowFlag forState:UIControlStateNormal];
                    [button setBackgroundImage:self.imageForYellowFlag forState:UIControlStateHighlighted];
                }
            }
            
            // set the button's target to this table view controller so we can interpret touch events and map that to a NSIndexSet
            [button addTarget:self action:@selector(accessoryButtonTapped:withEvent:) forControlEvents:UIControlEventTouchUpInside];
            
            //[button setBackgroundColor:[UIColor greenColor]];
            
            cell.accessoryView = button;
        }
        else {
            
            UIButton *button = [UIButton buttonWithType:UIButtonTypeCustom];
            
            //CGRect frame = CGRectMake(0.0, 0.0, imageForSelectedRow.size.width, imageForSelectedRow.size.height);
            CGRect frame = CGRectMake(0.0, 0.0, 45, 50);
            button.frame = frame;    // match the button's size with the image size
            
            [button setBackgroundImage:self.imageForSelectedRow forState:UIControlStateNormal];
            [button setBackgroundImage:self.imageForUnselectedRow forState:UIControlStateHighlighted];
            [button setUserInteractionEnabled:NO];
            //[button setBackgroundColor:[UIColor blueColor]];
            
            cell.accessoryView = button;
            
        }
        
        return cell;
    }
    else {
        static NSString *cellId = @"PreviousSearchtCell";
        UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellId];
        if (!cell)
            cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:cellId];
        
        cell.textLabel.text = @"Tarte";
        
        return cell;
    }
    
	return nil;
}

#pragma mark - Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    self.pressedIndexPath = indexPath;
    
    NSMutableArray *arrayActionsMessages = [NSMutableArray array];
    
    Topic *aTopic = [self.arrayData objectAtIndex:indexPath.row];
    
    if (aTopic.sLastSearchPostURL.length > 0) {
        [arrayActionsMessages addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"Dernière correspondance", @"lastSearchPostAction", nil] forKeys:[NSArray arrayWithObjects:@"title", @"code", nil]]];
    }
    if (aTopic.aURLOfFlag.length > 0) {
        [arrayActionsMessages addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"Drapeau", @"flagAction", nil] forKeys:[NSArray arrayWithObjects:@"title", @"code", nil]]];
    }
    
    [arrayActionsMessages addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"Première page", @"firstPageAction", nil] forKeys:[NSArray arrayWithObjects:@"title", @"code", nil]]];
    [arrayActionsMessages addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"Dernière page", @"lastPageAction", nil] forKeys:[NSArray arrayWithObjects:@"title", @"code", nil]]];
    [arrayActionsMessages addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"Dernière réponse", @"lastPostAction", nil] forKeys:[NSArray arrayWithObjects:@"title", @"code", nil]]];
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
    }
    else {
        UITableViewCell *cell = [tableView cellForRowAtIndexPath:indexPath];
        CGRect cellRectInTableView = [tableView rectForRowAtIndexPath:indexPath];
        CGPoint centerInTableView = cell.center;
        CGPoint pointLocation = [tableView convertPoint:centerInTableView toView:tableView.superview];
        CGRect origFrame = CGRectMake( pointLocation.x, pointLocation.y, 1, 1);
        self.topicActionAlert.popoverPresentationController.sourceView = self.view;
        self.topicActionAlert.popoverPresentationController.sourceRect = origFrame;
        self.topicActionAlert.popoverPresentationController.backgroundColor = [ThemeColors alertBackgroundColor:[[ThemeManager sharedManager] theme]];
    }

    [self presentViewController:self.topicActionAlert animated:YES completion:nil];
    [[ThemeManager sharedManager] applyThemeToAlertController:self.topicActionAlert];
}

- (void)pushTopic
{
    self.navigationItem.backBarButtonItem =
    [[UIBarButtonItem alloc] initWithTitle:@" "
                                     style: UIBarButtonItemStylePlain
                                    target:nil
                                    action:nil];
    
    [self.navigationController pushViewController:self.messagesTableViewController animated:YES];
    /*
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
    {
        self.navigationItem.backBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@" "
                                         style: UIBarButtonItemStylePlain
                                        target:nil
                                        action:nil];
        
        [self.navigationController pushViewController:self.messagesTableViewController animated:YES];
    }
    else if (self.detailNavigationViewController)
    {
        self.messagesTableViewController.navigationItem.leftBarButtonItem = self.detailNavigationViewController.splitViewController.displayModeButtonItem;
        self.messagesTableViewController.navigationItem.leftItemsSupplementBackButton = YES;
        [self.detailNavigationViewController setViewControllers:[NSMutableArray arrayWithObjects:self.messagesTableViewController, nil] animated:YES];

        // Close left panel on ipad in portrait mode
        [[HFRplusAppDelegate sharedAppDelegate] hidePrimaryPanelOnIpadForSplitViewController:self.detailNavigationViewController.splitViewController];
    }*/
}

#pragma mark - Action delegate

-(void)lastSearchPostAction {
    [self openTopicWithURL:[[self.arrayData objectAtIndex:self.pressedIndexPath.row] sLastSearchPostURL]];
}

-(void)flagAction {
    [self openTopicWithURL:[[self.arrayData objectAtIndex:self.pressedIndexPath.row] aURLOfFlag]];
}

-(void)firstPageAction {
    [self openTopicWithURL:[[self.arrayData objectAtIndex:self.pressedIndexPath.row] aURL]];
}

-(void)lastPageAction {
    [self openTopicWithURL:[[self.arrayData objectAtIndex:self.pressedIndexPath.row] aURLOfLastPage]];
}

-(void)lastPostAction {
    [self openTopicWithURL:[[self.arrayData objectAtIndex:self.pressedIndexPath.row] aURLOfLastPost]];
}

-(void)openTopicWithURL:(NSString*)sURL {
    NSLog(@"Push topic with URL %@", sURL);
    MessagesTableViewController *aView = [[MessagesTableViewController alloc] initWithNibName:@"MessagesTableViewController" bundle:nil andUrl:sURL];
    self.messagesTableViewController = aView;
    
    self.messagesTableViewController.topicName = [[self.arrayData objectAtIndex:self.pressedIndexPath.row] aTitle];
    self.messagesTableViewController.isViewed = [[self.arrayData objectAtIndex:self.pressedIndexPath.row] isViewed];
    
    [self pushTopic];
    [self setTopicViewed];
}

-(void)copyLinkAction {
    NSLog(@"copier lien page 1");
    
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = [NSString stringWithFormat:@"%@%@", [k RealForumURL], [[self.arrayData objectAtIndex:self.pressedIndexPath.row] aURL]];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleAlert];
    NSMutableAttributedString * message = [[NSMutableAttributedString alloc] initWithString:@"Lien copié dans le presse-papiers"];
    [message addAttribute:NSForegroundColorAttributeName value:[ThemeColors textColor:[[ThemeManager sharedManager] theme]] range:(NSRange){0, [message.string length]}];
    [alert setValue:message forKey:@"attributedMessage"];
    [self presentViewController:alert animated:YES completion:^{
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 0.3 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
            [alert dismissViewControllerAnimated:YES completion:nil];
        });
    }];
    [[ThemeManager sharedManager] applyThemeToAlertController:alert];
    
}

-(void)setTopicViewed {

    if (self.pressedIndexPath && self.arrayData.count > 0 && [self.pressedIndexPath row] <= self.arrayData.count) {
        [[self.arrayData objectAtIndex:[self.pressedIndexPath row]] setIsViewed:YES];
        
        NSArray* rowsToReload = [NSArray arrayWithObjects:self.pressedIndexPath, nil];
        [self.topicsTableView reloadRowsAtIndexPaths:rowsToReload withRowAnimation:UITableViewRowAnimationNone];
    }
    else if (self.topicsTableView.indexPathForSelectedRow && self.arrayData.count > 0 && [self.topicsTableView.indexPathForSelectedRow row] <= self.arrayData.count) {
        [[self.arrayData objectAtIndex:[self.topicsTableView.indexPathForSelectedRow row]] setIsViewed:YES];
        
        NSArray* rowsToReload = [NSArray arrayWithObjects:self.topicsTableView.indexPathForSelectedRow, nil];
        [self.topicsTableView reloadRowsAtIndexPaths:rowsToReload withRowAnimation:UITableViewRowAnimationNone];
    }
}


#pragma mark -
#pragma mark chooseTopicPage

-(void)chooseTopicPage {
    //NSLog(@"chooseTopicPage Topics");
    
    UIAlertController * alertController = [UIAlertController alertControllerWithTitle: nil
                                                                              message: nil
                                                                       preferredStyle:UIAlertControllerStyleAlert];
    NSMutableAttributedString * message = [[NSMutableAttributedString alloc] initWithString:@"Aller à la page"];
    [message addAttribute:NSForegroundColorAttributeName value:[ThemeColors textColor:[[ThemeManager sharedManager] theme]] range:(NSRange){0, [message.string length]}];
    [alertController setValue:message forKey:@"attributedTitle"];
    [alertController addTextFieldWithConfigurationHandler:^(UITextField *textField) {
        textField.placeholder = [NSString stringWithFormat:@"(numéro entre 1 et %d)", [[self.arrayData objectAtIndex:self.pressedIndexPath.row] maxTopicPage]];
        [[ThemeManager sharedManager] applyThemeToTextField:textField];
        textField.textAlignment = NSTextAlignmentCenter;
        textField.delegate = self;
        [textField addTarget:self action:@selector(textFieldTopicDidChange:) forControlEvents:UIControlEventEditingChanged];
        textField.keyboardAppearance = [ThemeColors keyboardAppearance:[[ThemeManager sharedManager] theme]];
        textField.keyboardType = UIKeyboardTypeNumberPad;
        
    }];
    
    [alertController addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        NSArray * textfields = alertController.textFields;
        UITextField * pagefield = textfields[0];
        int pageNumber = [[pagefield text] intValue];
        [self gotoPageNumber:pageNumber];
        
    }]];
    [alertController addAction:[UIAlertAction actionWithTitle:@"Annuler"
                                                        style:UIAlertActionStyleCancel
                                                      handler:^(UIAlertAction * _Nonnull action) {
                                                          [alertController dismissViewControllerAnimated:YES completion:nil];
                                                      }]];
    
    [[ThemeManager sharedManager] applyThemeToAlertController:alertController];
    [self presentViewController:alertController animated:YES completion:^{
        if([[ThemeManager sharedManager] theme] == ThemeDark){
            for (UIView* textfield in alertController.textFields) {
                UIView *container = textfield.superview;
                UIView *effectView = container.superview.subviews[0];
                
                if (effectView && [effectView class] == [UIVisualEffectView class]){
                    container.backgroundColor = [UIColor clearColor];
                    [effectView removeFromSuperview];
                }
            }
        }
    }];
    
    
    
    
}

-(void)textFieldTopicDidChange:(id)sender {
    //NSLog(@"textFieldDidChange %d %@", [[(UITextField *)sender text] intValue], sender);
    
    
    if ([[(UITextField *)sender text] length] > 0) {
        int val;
        if ([[NSScanner scannerWithString:[(UITextField *)sender text]] scanInt:&val]) {
            //NSLog(@"int %d %@ %@", val, [(UITextField *)sender text], [NSString stringWithFormat:@"%d", val]);
            
            if (![[(UITextField *)sender text] isEqualToString:[NSString stringWithFormat:@"%d", val]]) {
                //NSLog(@"pas int");
                [sender setText:[NSString stringWithFormat:@"%d", val]];
            }
            else if ([[(UITextField *)sender text] intValue] < 1) {
                //NSLog(@"ERROR WAS %d", [[(UITextField *)sender text] intValue]);
                [sender setText:[NSString stringWithFormat:@"%d", 1]];
                //NSLog(@"ERROR NOW %d", [[(UITextField *)sender text] intValue]);
                
            }
            else if ([[(UITextField *)sender text] intValue] > [[self.arrayData objectAtIndex:self.pressedIndexPath.row] maxTopicPage]) {
                //NSLog(@"ERROR WAS %d", [[(UITextField *)sender text] intValue]);
                [sender setText:[NSString stringWithFormat:@"%d", [[self.arrayData objectAtIndex:self.pressedIndexPath.row] maxTopicPage]]];
                //NSLog(@"ERROR NOW %d", [[(UITextField *)sender text] intValue]);
                
            }
            else {
                //NSLog(@"OK");
            }
        }
        else {
            [sender setText:@""];
        }
    }
}

-(void)gotoPageNumber:(int)number{
    NSString * newUrl = [[NSString alloc] initWithString:[[self.arrayData objectAtIndex:self.pressedIndexPath.row] aURL]];
    newUrl = [newUrl stringByReplacingOccurrencesOfString:@"_1.htm" withString:[NSString stringWithFormat:@"_%d.htm", number]];
    newUrl = [newUrl stringByReplacingOccurrencesOfString:@"page=1&" withString:[NSString stringWithFormat:@"page=%d&",number]];
    newUrl = [newUrl stringByRemovingAnchor];
    
    [self openTopicWithURL:[[self.arrayData objectAtIndex:self.pressedIndexPath.row] aURL]];
}

@end
