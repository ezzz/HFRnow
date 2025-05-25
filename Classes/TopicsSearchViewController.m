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

#define TIME_OUT_INTERVAL_SEARCH 15

@implementation TopicsSearchViewController

@synthesize stories;
@synthesize request;
@synthesize disableViewOverlay;
@synthesize status, statusMessage, messagesTableViewController, detailNavigationViewController, tmpCell, pressedIndexPath, topicActionSheet, topicActionAlert;
@synthesize imageForRedFlag, imageForYellowFlag, imageForBlueFlag, imageForGreyFlag;
@synthesize textSearchBar, optionSearchTypeSegmentedControl, optionSearchInSegmentedControl, optionSearchFromSegmentedControl, item;// currentElement, currentSummary, currentUrl, currentTitle, currentDate, currentSummary, currentLink, item;

#pragma mark - ViewController Methods

- (void)viewDidLoad {
    [super viewDidLoad];
    
    self.title = @"Recherche";
    self.searchVisible = YES; // Visible par défaut

    // Mettre à jour l'icône du bouton
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(toggleSearchFields)];

    // 1. Ajouter la SearchBar
    self.textSearchBar = [[UISearchBar alloc] init]; //initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, 44)];
    self.textSearchBar.placeholder = @"Recherche";
    self.textSearchBar.delegate = self;
    self.textSearchBar.autocapitalizationType = UITextAutocapitalizationTypeNone;
    if ([self.textSearchBar respondsToSelector:@selector(setSearchBarStyle:)]) {
        self.textSearchBar.searchBarStyle = UISearchBarStyleMinimal;
    }
    
    self.textSearchBar.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.textSearchBar];

    // Contraintes Auto Layout
    [NSLayoutConstraint activateConstraints:@[
        [self.textSearchBar.topAnchor constraintEqualToAnchor:self.view.safeAreaLayoutGuide.topAnchor constant:6],
        [self.textSearchBar.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor],
        [self.textSearchBar.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor],
        [self.textSearchBar.heightAnchor constraintEqualToConstant:44]
    ]];
    
    [self.textSearchBar becomeFirstResponder];

    // 2. Ajouter le SegmentedControl juste en dessous
    optionSearchTypeSegmentedControl, optionSearchInSegmentedControl, optionSearchFromSegmentedControl;
    
    NSArray *items1 = @[@"Tous les mots", @"Au moins un mot", @"Avancé"];
    self.optionSearchTypeSegmentedControl = [[UISegmentedControl alloc] initWithItems:items1];
    self.optionSearchTypeSegmentedControl.selectedSegmentIndex = 0;
    [self.optionSearchTypeSegmentedControl addTarget:self action:@selector(segmentedControlChanged:) forControlEvents:UIControlEventValueChanged];
    self.optionSearchTypeSegmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.optionSearchTypeSegmentedControl];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.optionSearchTypeSegmentedControl.topAnchor constraintEqualToAnchor:self.textSearchBar.bottomAnchor constant:12],
        [self.optionSearchTypeSegmentedControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.optionSearchTypeSegmentedControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.optionSearchTypeSegmentedControl.heightAnchor constraintEqualToConstant:30]
    ]];

    NSArray *items2 = @[@"Titre et contenu", @"Titre", @"Contenu"];
    self.optionSearchInSegmentedControl = [[UISegmentedControl alloc] initWithItems:items2];
    self.optionSearchInSegmentedControl.selectedSegmentIndex = 0;
    [self.optionSearchInSegmentedControl addTarget:self action:@selector(segmentedControlChanged:) forControlEvents:UIControlEventValueChanged];
    self.optionSearchInSegmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.optionSearchInSegmentedControl];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.optionSearchInSegmentedControl.topAnchor constraintEqualToAnchor:self.optionSearchTypeSegmentedControl.bottomAnchor constant:16],
        [self.optionSearchInSegmentedControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.optionSearchInSegmentedControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.optionSearchInSegmentedControl.heightAnchor constraintEqualToConstant:30]
    ]];

    NSArray *items3 = @[@"Début", @"5 ans", @"1 an"];
    self.optionSearchFromSegmentedControl = [[UISegmentedControl alloc] initWithItems:items3];
    self.optionSearchFromSegmentedControl.selectedSegmentIndex = 0;
    [self.optionSearchFromSegmentedControl addTarget:self action:@selector(segmentedControlChanged:) forControlEvents:UIControlEventValueChanged];
    self.optionSearchFromSegmentedControl.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:self.optionSearchFromSegmentedControl];
    
    [NSLayoutConstraint activateConstraints:@[
        [self.optionSearchFromSegmentedControl.topAnchor constraintEqualToAnchor:self.optionSearchInSegmentedControl.bottomAnchor constant:16],
        [self.optionSearchFromSegmentedControl.leadingAnchor constraintEqualToAnchor:self.view.leadingAnchor constant:16],
        [self.optionSearchFromSegmentedControl.trailingAnchor constraintEqualToAnchor:self.view.trailingAnchor constant:-16],
        [self.optionSearchFromSegmentedControl.heightAnchor constraintEqualToConstant:30]
    ]];


    // 3. TableView – pour historique
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
    ]];
    self.stories =[[NSMutableArray alloc]init];
    self.disableViewOverlay = [[UIView alloc]
                               initWithFrame:CGRectMake(0.0f,0.0f,1000.0f,1000.0f)];
    self.disableViewOverlay.backgroundColor=[UIColor blackColor];
    self.disableViewOverlay.alpha = 0;
    
    self.disableViewOverlay.autoresizingMask = (UIViewAutoresizingFlexibleWidth);
    
    UITapGestureRecognizer *tapRecognizer = [[UITapGestureRecognizer alloc]
                                                         initWithTarget:self action:@selector(handleTap:)];
    [self.disableViewOverlay addGestureRecognizer:tapRecognizer];
    
    [self.maintenanceView setText:@"Aucun résultat"];
    
    self.arrayData = [[NSMutableArray alloc] init];
    self.arrayNewData = [[NSMutableArray alloc] init];
    
    self.imageForUnselectedRow = [UIImage imageNamed:@"selectedrow"];
    self.imageForSelectedRow = [UIImage imageNamed:@"unselectedrow"];
    
    self.imageForRedFlag = [UIImage imageNamed:@"Flat-RedFlag-25"];
    self.imageForYellowFlag = [UIImage imageNamed:@"Flat-YellowFlag-25"];
    self.imageForBlueFlag = [UIImage imageNamed:@"Flat-CyanFlag-25"];
}


- (void) viewWillAppear:(BOOL)animated
{
    //[self.navigationController setNavigationBarHidden:YES animated:animated];
    [super viewWillAppear:animated];
    Theme theme = [[ThemeManager sharedManager] theme];
    self.view.backgroundColor = self.maintenanceView.backgroundColor = self.loadingView.backgroundColor = self.topicsTableView.backgroundColor = [ThemeColors greyBackgroundColor:theme];
    self.optionSearchInSegmentedControl.backgroundColor = self.optionSearchFromSegmentedControl.backgroundColor = self.optionSearchTypeSegmentedControl.backgroundColor = self.textSearchBar.backgroundColor = [ThemeColors greyBackgroundColor:theme];
    

    self.topicsTableView.separatorColor = [ThemeColors cellBorderColor:theme];

    if (self.messagesTableViewController) {
        
        self.messagesTableViewController = nil;
    }
}

- (void)toggleSearchFields {
    self.searchVisible = !self.searchVisible;
    self.textSearchBar.hidden = !self.searchVisible;
    self.optionSearchTypeSegmentedControl.hidden = !self.searchVisible;
    self.optionSearchInSegmentedControl.hidden = !self.searchVisible;
    self.optionSearchFromSegmentedControl.hidden = !self.searchVisible;
    self.historicTableView.hidden = !self.searchVisible;
    
    if (self.searchVisible) {
        [self cancelFetchContent];
        [self.textSearchBar becomeFirstResponder];
    }
    
    // Si tu utilises Auto Layout :
    [self.view setNeedsLayout];
    [self.view layoutIfNeeded];
}

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
    searchBar.text=@"";
    [self searchBar:searchBar activate:NO];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    // Do the search and show the results in tableview
    // Deactivate the UISearchBar
    
    // You'll probably want to do this on another thread
    // SomeService is just a dummy class representing some
    // api that you are using to do the search


    [self searchBar:searchBar activate:NO];
    
    [self fetchContent];
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
        [disableViewOverlay removeFromSuperview];
        [searchBar resignFirstResponder];
    } else {

        self.disableViewOverlay.alpha = 0;
        [self.view addSubview:self.disableViewOverlay];
        
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

#pragma mark - Data lifecycle

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

- (void)fetchContent {
    NSLog(@"SEARCH fetchContent");

	[self.stories removeAllObjects];
	
    self.searchVisible = YES;
    [self toggleSearchFields];
    self.maintenanceView.hidden = YES;
    self.topicsTableView.hidden = YES;
    self.loadingView.hidden = NO;
    
    // Mettre à jour l'icône du bouton
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"xmark"]
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(cancelFetchContent)];

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
    NSLog(@"SEARCH followRedirectToURL 1 %@ <- %@", self.currentUrl, urlString);

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
        } else {
            NSLog(@"✅ Statut HTTP redirection : %ld", (long)[(NSHTTPURLResponse *)response statusCode]);
            /*
            NSString *html = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
            NSUInteger length = html.length;
            NSUInteger blockSize = 1000;
            for (NSUInteger i = 0; i < length; i += blockSize) {
                NSUInteger thisBlockSize = MIN(blockSize, length - i);
                NSString *block = [html substringWithRange:NSMakeRange(i, thisBlockSize)];
                NSLog(@"🧩 Bloc %lu : %@", (unsigned long)(i / blockSize + 1), block);
            }
            */
            // Parse result
            [self parseSearchResult:data];
            
            [self.arrayData removeAllObjects];
            self.arrayData = [NSMutableArray arrayWithArray:self.arrayNewData];
            [self.arrayNewData removeAllObjects];
            
            // 🧠 Appel de la méthode UI sur le thread principal
            dispatch_async(dispatch_get_main_queue(), ^{
                NSLog(@"How many results:%ld", [self.arrayData count]);

                if ([self.arrayData count] == 0) {
                    [self.maintenanceView setText:@"Aucun résultat"];
                    [self.maintenanceView setHidden:NO];
                    [self.topicsTableView setHidden:YES];
                    [self.loadingView setHidden:YES];
                }
                else {
                    NSLog(@"Show results");
                    [self.maintenanceView setHidden:YES];
                    [self.topicsTableView setHidden:NO];
                    [self.loadingView setHidden:YES];
                }
                
                // Mettre à jour l'icône du bouton
                // Mettre à jour l'icône du bouton
                self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
                    initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]
                    style:UIBarButtonItemStylePlain
                    target:self
                    action:@selector(toggleSearchFields)];
                
                [self.topicsTableView reloadData];
                            
                [(UISegmentedControl *)[self.navigationItem.titleView.subviews objectAtIndex:0] setUserInteractionEnabled:YES];
                [self cancelFetchContent];
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
    return nil;
}

-(void)parseSearchResult:(NSData *)contentData
{
    HTMLParser * myParser = [[HTMLParser alloc] initWithData:contentData error:NULL];
    HTMLNode * bodyNode = [myParser body];

    //NSLog(@"RawContentsOfNode %@", rawContentsOfNode([bodyNode _node], [myParser _doc]));
    
    /*
    if (![bodyNode getAttributeNamed:@"id"]) {
        NSDictionary *notif;
        
        if ([[[bodyNode firstChild] tagName] isEqualToString:@"p"]) {
            
            notif = [NSDictionary dictionaryWithObjectsAndKeys:   [NSNumber numberWithInt:kMaintenance], @"status",
                     [[[bodyNode firstChild] contents] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]], @"message", nil];
            
        }
        else {
            notif = [NSDictionary dictionaryWithObjectsAndKeys:   [NSNumber numberWithInt:kNoAuth], @"status",
                     [[[bodyNode findChildWithAttribute:@"class" matchingName:@"hop" allowPartial:NO] contents] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]], @"message", nil];
            
        }
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kStatusChangedNotification object:self userInfo:notif];
        
        return;
    }

    
    //MP
    BOOL needToUpdateMP = NO;
    HTMLNode *MPNode = [bodyNode findChildOfClass:@"none"]; //Get links for cat
    NSArray *temporaryMPArray = [MPNode findChildTags:@"td"];
    
    if (temporaryMPArray.count == 3) {
        
        NSString *regExMP = @"[^.0-9]+([0-9]{1,})[^.0-9]+";
        NSString *myMPNumber = [[[temporaryMPArray objectAtIndex:1] allContents] stringByReplacingOccurrencesOfRegex:regExMP
                                                                                                          withString:@"$1"];
        
        [[HFRplusAppDelegate sharedAppDelegate] updateMPBadgeWithString:myMPNumber];
    }
    else {
        if ([self isKindOfClass:[HFRMPViewController class]]) {
            needToUpdateMP = YES;
        }
    }
    //MP
     */

    
    //On remplace le numéro de page dans le titre
    NSString *regexString  = @".*page=([^&]+).*";
    NSRange   matchedRange;// = NSMakeRange(NSNotFound, 0UL);
    NSRange   searchRange = NSMakeRange(0, self.currentUrl.length);
    NSError  *error2        = NULL;
    //int numPage;
    
    matchedRange = [self.currentUrl rangeOfRegex:regexString options:RKLNoOptions inRange:searchRange capture:1L error:&error2];
    
    if (matchedRange.location == NSNotFound) {
        NSRange rangeNumPage =  [[self currentUrl] rangeOfCharactersFromSet:[NSCharacterSet decimalDigitCharacterSet] options:NSBackwardsSearch];
        self.pageNumber = [[self.currentUrl substringWithRange:rangeNumPage] intValue];
    }
    else {
        self.pageNumber = [[self.currentUrl substringWithRange:matchedRange] intValue];
        
    }
    
    if (self.pageNumber == 0) {
        self.pageNumber = 1;
    }
    
    /*
    //New Topic URL
    HTMLNode * forumNewTopicNode = [bodyNode findChildWithAttribute:@"id" matchingName:@"md_btn_new_topic" allowPartial:NO];
    forumNewTopicUrl = [forumNewTopicNode getAttributeNamed:@"href"];

    if(forumNewTopicUrl.length > 0) self.navigationItem.rightBarButtonItem.enabled = YES;
    //-

    //Filtres
    HTMLNode *FiltresNode =        [bodyNode findChildWithAttribute:@"class" matchingName:@"cadreonglet" allowPartial:NO];
    
    if([FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet1" allowPartial:NO]) self.forumBaseURL = [[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet1" allowPartial:NO] getAttributeNamed:@"href"];
    
    if ([[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet2" allowPartial:NO] getAttributeNamed:@"href"]) {
        if(!self.forumFavorisURL)    self.forumFavorisURL = [[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet2" allowPartial:NO] getAttributeNamed:@"href"];
        [(UISegmentedControl *)[self.navigationItem.titleView.subviews objectAtIndex:0] setEnabled:YES forSegmentAtIndex:1];
    }
    else {
        [(UISegmentedControl *)[self.navigationItem.titleView.subviews objectAtIndex:0] setEnabled:NO forSegmentAtIndex:1];
    }

    if ([[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet3" allowPartial:NO] getAttributeNamed:@"href"]) {
        if(!self.forumFlag1URL)        self.forumFlag1URL = [[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet3" allowPartial:NO] getAttributeNamed:@"href"];
        [(UISegmentedControl *)[self.navigationItem.titleView.subviews objectAtIndex:0] setEnabled:YES forSegmentAtIndex:2];
    }
    else {
        [(UISegmentedControl *)[self.navigationItem.titleView.subviews objectAtIndex:0] setEnabled:NO forSegmentAtIndex:2];
    }

    if ([[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet4" allowPartial:NO] getAttributeNamed:@"href"]) {
        if(!self.forumFlag0URL)        self.forumFlag0URL = [[FiltresNode findChildWithAttribute:@"id" matchingName:@"onglet4" allowPartial:NO] getAttributeNamed:@"href"];
        [(UISegmentedControl *)[self.navigationItem.titleView.subviews objectAtIndex:0] setEnabled:YES forSegmentAtIndex:3];
    }
    else {
        [(UISegmentedControl *)[self.navigationItem.titleView.subviews objectAtIndex:0] setEnabled:NO forSegmentAtIndex:3];
    }
    //NSLog(@"Filtres1Node %@", rawContentsOfNode([Filtres1Node _node], [myParser _doc]));
    //-- FIN Filtre
*/
    
    HTMLNode * pagesTrNode = [bodyNode findChildWithAttribute:@"class" matchingName:@"fondForum1PagesHaut" allowPartial:YES];

    if(pagesTrNode)
    {
        HTMLNode * pagesLinkNode = [pagesTrNode findChildWithAttribute:@"class" matchingName:@"left" allowPartial:NO];
        
        //NSLog(@"pagesLinkNode %@", rawContentsOfNode([pagesLinkNode _node], [myParser _doc]));

        if (pagesLinkNode) {
            NSLog(@"pagesLinkNode %@", rawContentsOfNode([pagesLinkNode _node], [myParser _doc]));
            
            //NSArray *temporaryNumPagesArray = [[NSArray alloc] init];
            NSArray *temporaryNumPagesArray = [pagesLinkNode children];
            
            [self setFirstPageNumber:[[[temporaryNumPagesArray objectAtIndex:2] contents] intValue]];
            
            NSLog(@"pageNumber %d firstpage %d", self.pageNumber, [[[temporaryNumPagesArray objectAtIndex:2] contents] intValue]);
            NSLog(@"currentUrl %@", self.currentUrl);
            if ([self pageNumber] == [self firstPageNumber]) {
                [self setFirstPageUrl:self.currentUrl];
            }
            else {
                NSString *newFirstPageUrl;
                NSLog(@"tagname %@", [[temporaryNumPagesArray objectAtIndex:2] tagName]);

                if ([[[temporaryNumPagesArray objectAtIndex:2] tagName] isEqualToString:@"span"]) {
                    newFirstPageUrl = [[NSString alloc] initWithString:[[[temporaryNumPagesArray objectAtIndex:2] className] decodeSpanUrlFromString2]];
                }
                else {
                    newFirstPageUrl = [[NSString alloc] initWithString:[[temporaryNumPagesArray objectAtIndex:2] getAttributeNamed:@"href"]];
                }
                
                [self setFirstPageUrl:newFirstPageUrl];
            }
            
            [self setLastPageNumber:[[[temporaryNumPagesArray lastObject] contents] intValue]];
            
            if ([self pageNumber] == [self lastPageNumber]) {
                NSString *newLastPageUrl = [[NSString alloc] initWithString:[self currentUrl]];
                [self setLastPageUrl:newLastPageUrl];
            }
            else {
                NSString *newLastPageUrl;
                
                if ([[[temporaryNumPagesArray lastObject] tagName] isEqualToString:@"span"]) {
                    newLastPageUrl = [[NSString alloc] initWithString:[[[temporaryNumPagesArray lastObject] className] decodeSpanUrlFromString2]];
                }
                else {
                    newLastPageUrl = [[NSString alloc] initWithString:[[temporaryNumPagesArray lastObject] getAttributeNamed:@"href"]];
                }
                
                [self setLastPageUrl:newLastPageUrl];
            }
            
            
            //TableFooter
            dispatch_async(dispatch_get_main_queue(), ^{

                UIToolbar *tmptoolbar = [[UIToolbar alloc] initWithFrame:CGRectMake(0, 0, 320, 44)];
                tmptoolbar.barStyle = -1;
                tmptoolbar.opaque = NO;
                tmptoolbar.translucent = YES;

                if (tmptoolbar.subviews.count > 1) {
                    [[tmptoolbar.subviews objectAtIndex:1] setHidden:YES];
                }

                [tmptoolbar setBackgroundImage:[ThemeColors imageFromColor:[ThemeColors toolbarPageBackgroundColor:[[ThemeManager sharedManager] theme]]] forToolbarPosition:UIBarPositionAny barMetrics:UIBarMetricsDefault];
                [tmptoolbar setShadowImage:[UIImage new] forToolbarPosition:UIBarPositionAny];
                [tmptoolbar sizeToFit];

                UIBarButtonItem *systemItemNext = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"arrowforward"]
                                                                                   style:UIBarButtonItemStyleBordered
                                                                                  target:self
                                                                                  action:@selector(nextPage:)];
                
                UIBarButtonItem *systemItemPrevious = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"arrowback"]
                                                                                   style:UIBarButtonItemStyleBordered
                                                                                  target:self
                                                                                  action:@selector(previousPage:)];

                
                UIBarButtonItem *systemItem1 = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"arrowbegin"]
                                                                                       style:UIBarButtonItemStyleBordered
                                                                                      target:self
                                                                                      action:@selector(firstPage:)];
                
                if ([self pageNumber] == [self firstPageNumber]) {
                    [systemItem1 setEnabled:NO];
                    [systemItemPrevious setEnabled:NO];
                }
                
                UIBarButtonItem *systemItem2 = [[UIBarButtonItem alloc] initWithImage:[UIImage imageNamed:@"arrowend"]
                                                                                style:UIBarButtonItemStyleBordered
                                                                               target:self
                                                                               action:@selector(lastPage:)];
                
                //systemItem2.imageInsets = UIEdgeInsetsMake(2.0, 0, -2.0, 0);

                if ([self pageNumber] == [self lastPageNumber]) {
                    [systemItem2 setEnabled:NO];
                    [systemItemNext setEnabled:NO];
                }

                UIButton *labelBtn = [UIButton buttonWithType:UIButtonTypeCustom];
                labelBtn.frame = CGRectMake(0, 0, 130, 44);
                [labelBtn addTarget:self action:@selector(choosePage) forControlEvents:UIControlEventTouchUpInside];
                [labelBtn setTitle:[NSString stringWithFormat:@"%d/%d", [self pageNumber], [self lastPageNumber]] forState:UIControlStateNormal];
                
                [[labelBtn titleLabel] setFont:[UIFont boldSystemFontOfSize:16.0]];
                [labelBtn setTitleColor:[ThemeColors cellIconColor:[[ThemeManager sharedManager] theme]] forState:UIControlStateNormal];
                UIBarButtonItem *systemItem3 = [[UIBarButtonItem alloc] initWithCustomView:labelBtn];
                
                //Use this to put space in between your toolbox buttons
                UIBarButtonItem *flexItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFlexibleSpace
                                                                                          target:nil
                                                                                          action:nil];
                UIBarButtonItem *fixItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemFixedSpace
                                                                                          target:nil
                                                                                          action:nil];
                fixItem.width = SPACE_FOR_BARBUTTON;
                
                //Add buttons to the array
                NSArray *items = [NSArray arrayWithObjects: systemItem1, fixItem, systemItemPrevious, flexItem, systemItem3, flexItem, systemItemNext, fixItem, systemItem2, nil];
                [tmptoolbar setItems:items animated:NO];
                if ([self firstPageNumber] != [self lastPageNumber]) {
                    if (![self.topicsTableView viewWithTag:666777]) {
                        CGRect frame = self.topicsTableView.bounds;
                        frame.origin.y = -frame.size.height;
                        UIView* grayView = [[UIView alloc] initWithFrame:frame];
                        grayView.tag = 666777;
                        grayView.backgroundColor = [ThemeColors addMessageBackgroundColor:[[ThemeManager sharedManager] theme]];
                        [self.topicsTableView insertSubview:grayView atIndex:0];
                    }

                    [self.topicsTableView setBackgroundColor:[ThemeColors addMessageBackgroundColor:[[ThemeManager sharedManager] theme]]];
                    self.topicsTableView.tableFooterView = tmptoolbar;
                }
                else {
                    self.topicsTableView.tableFooterView = [[UIView alloc] initWithFrame:CGRectZero];
                }
            });

        }
        
        //Gestion des pages
        NSArray *temporaryPagesArray = [pagesTrNode findChildrenWithAttribute:@"class" matchingName:@"pagepresuiv" allowPartial:YES];
        if(temporaryPagesArray.count != 2)
        {
            NSLog(@"SEARCH Next page PAS 2", self.nextPageUrl);
        }
        else {
            HTMLNode *nextUrlNode = [[temporaryPagesArray objectAtIndex:0] findChildWithAttribute:@"class" matchingName:@"md_cryptlink" allowPartial:YES];

            if (nextUrlNode) {
                self.nextPageUrl = [[nextUrlNode className] decodeSpanUrlFromString2];
                NSLog(@"SEARCH Next page URL %@", self.nextPageUrl);
            }
            else {
                self.nextPageUrl = @"";
                NSLog(@"SEARCH Next page is null", self.nextPageUrl);
            }
            
            HTMLNode *previousUrlNode = [[temporaryPagesArray objectAtIndex:1] findChildWithAttribute:@"class" matchingName:@"md_cryptlink" allowPartial:YES];
            
            if (previousUrlNode) {
                
                self.previousPageUrl = [[previousUrlNode className] decodeSpanUrlFromString2];
                //TODO SEARCH add swipeLeftRecognizer [self.view addGestureRecognizer:swipeRightRecognizer];
                //NSLog(@"previousPageUrl = %@", self.previousPageUrl);

            }
            else {
                self.previousPageUrl = @"";
            }

        }
    }
    
    NSArray *temporaryTopicsArray = [bodyNode findChildrenWithAttribute:@"class" matchingName:@"sujet ligne_booleen" allowPartial:YES]; //Get links for cat
    if (temporaryTopicsArray.count == 0) {
        //NSLog(@"Aucun nouveau message %d", self.arrayDataID.count);
        NSLog(@"kNoResults");
        
        NSDictionary *notif = [NSDictionary dictionaryWithObjectsAndKeys:   [NSNumber numberWithInt:kNoResults], @"status",
                               @"Aucun message", @"message", nil];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kStatusChangedNotification object:self userInfo:notif];
        return;
    }
    else {
        //NSLog(@"PARSING Found %ld results", temporaryTopicsArray.count);

    }
    
    //Date du jour
    NSDate *nowTopic = [[NSDate alloc] init];
    NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
    [dateFormat setDateFormat:@"dd-MM-yyyy"];
    int countViewed = 0;
    

    for (HTMLNode * topicNode in temporaryTopicsArray) { //Loop through all the tags
        
        @autoreleasepool {

            Topic *aTopic = [[Topic alloc] init];
            
            //Title & URL
            HTMLNode * topicTitleNode = [topicNode findChildWithAttribute:@"class" matchingName:@"sujetCase3" allowPartial:NO];

            NSString *aTopicAffix = [NSString string];
            NSString *aTopicSuffix = [NSString string];

            
            if ([[topicNode className] rangeOfString:@"ligne_sticky"].location != NSNotFound) {
                aTopicAffix = [aTopicAffix stringByAppendingString:@""];//➫ ➥▶✚
                aTopic.isSticky = YES;
            }
            if ([topicTitleNode findChildWithAttribute:@"alt" matchingName:@"closed" allowPartial:NO]) {
                aTopicAffix = [aTopicAffix stringByAppendingString:@""];
                aTopic.isClosed = YES;
            }
            
            if (aTopicAffix.length > 0) {
                aTopicAffix = [aTopicAffix stringByAppendingString:@" "];
            }

            aTopicAffix = @"";

            // Title & Dernier Message correspondant
            NSArray *temporaryNumPagesArray = [topicNode findChildTags:@"a"];
            if (temporaryNumPagesArray.count > 1) {
                HTMLNode* NodetemporaryNumPagesArray[1];
            }
            
            NSArray *temporaryTopicLinksArray = [topicTitleNode findChildTags:@"a"];
            if (temporaryTopicLinksArray.count > 1) {
                HTMLNode* sSearchURL = (HTMLNode*)temporaryTopicLinksArray[1];
                NSLog(@"SEARCH sLastSearchPostURL href > %@", [sSearchURL getAttributeNamed:@"href"]);
                aTopic.sLastSearchPostURL = [sSearchURL getAttributeNamed:@"href"];
            }
            
            HTMLNode * topicExactTitleNode = [topicTitleNode findChildWithAttribute:@"class" matchingName:@"cCatTopic" allowPartial:NO];
            NSString *sExactTopicTitle = [topicExactTitleNode allContents];
            
            HTMLNode * searchContentNode = [topicTitleNode findChildWithAttribute:@"class" matchingName:@"s1" allowPartial:NO];
            if (searchContentNode) {
                aTopic.sLastSearchPostContent = [searchContentNode allContents];
                //NSLog(@"SEARCH FOUND     > %@, %@", sExactTopicTitle, aTopic.sLastSearchPostContent);
            }
            else {
                //NSLog(@"SEARCH NOT found > %@, %@", sExactTopicTitle, aTopic.sLastSearchPostContent);
            }
            [aTopic setATitle: [[NSString alloc] initWithFormat:@"%@%@%@", aTopicAffix, [sExactTopicTitle stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]], aTopicSuffix]];

            NSString *aTopicURL = [[NSString alloc] initWithString:[[topicTitleNode findChildTag:@"a"] getAttributeNamed:@"href"]];
            [aTopic setAURL:aTopicURL];

            
            //Answer Count
            HTMLNode * numRepNode = [topicNode findChildWithAttribute:@"class" matchingName:@"sujetCase7" allowPartial:NO];
            [aTopic setARepCount:[[numRepNode contents] intValue]];

            HTMLNode * pollImage = [topicNode findChildWithAttribute:@"src" matchingName:@"https://forum-images.hardware.fr/themes_static/images/defaut/sondage.gif" allowPartial:NO];
            if (pollImage != nil) {
                aTopic.isPoll = YES;
            }

            //Setup of Flag
            HTMLNode * topicFlagNode = [topicNode findChildWithAttribute:@"class" matchingName:@"sujetCase5" allowPartial:NO];
            HTMLNode * topicFlagLinkNode = [topicFlagNode findChildTag:@"a"];
            if (topicFlagLinkNode) {
                HTMLNode * topicFlagImgNode = [topicFlagLinkNode firstChild];

                NSString *aURLOfFlag = [[NSString alloc] initWithString:[topicFlagLinkNode getAttributeNamed:@"href"]];
                [aTopic setAURLOfFlag:aURLOfFlag];
                
                NSString *imgFlagSrc = [[NSString alloc] initWithString:[topicFlagImgNode getAttributeNamed:@"src"]];
                
                if (!([imgFlagSrc rangeOfString:@"flag0.gif"].location == NSNotFound)) {
                    [aTopic setATypeOfFlag:@"red"];
                }
                else if (!([imgFlagSrc rangeOfString:@"flag1.gif"].location == NSNotFound)) {
                    [aTopic setATypeOfFlag:@"blue"];
                }
                else if (!([imgFlagSrc rangeOfString:@"favoris.gif"].location == NSNotFound)) {
                    [aTopic setATypeOfFlag:@"yellow"];
                }
            
                // Read page of flag
                int pageNumber = 0;
                //Deux types d'URL:
                //https://forum.hardware.fr/hfr/Discussions/Viepratique/questions-avffuo-sujet_55667_14466.htm#t72765761
                //https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&subcat=432&post=55667&page=14466&p=1&sondage=0&owntopic=3&trash=0&trash_post=0&print=0&numreponse=0&quote_only=0&new=0&nojs=0#t72765761
                NSString *regexString  = @".*_(\\d+)\\.htm.*";
                if ([aTopic.aURLOfFlag hasPrefix:@"/forum2.php"]) {
                    regexString  = @".*page=([^&]+).*";
                }
                NSRange   matchedRange;// = NSMakeRange(NSNotFound, 0UL);
                NSRange   searchRange = NSMakeRange(0, aTopic.aURLOfFlag.length);
                NSError  *error2        = NULL;
                
                matchedRange = [aTopic.aURLOfFlag rangeOfRegex:regexString options:RKLNoOptions inRange:searchRange capture:1L error:&error2];
                
                if (matchedRange.location == NSNotFound) {
                    NSRange rangeNumPage =  [aTopic.aURLOfFlag rangeOfCharactersFromSet:[NSCharacterSet decimalDigitCharacterSet] options:NSBackwardsSearch];
                    pageNumber = [[aTopic.aURLOfFlag substringWithRange:rangeNumPage] intValue];
                }
                else {
                    pageNumber = [[aTopic.aURLOfFlag substringWithRange:matchedRange] intValue];
                    
                }
                //NSLog(@"Read page of flag %@", aTopic.aURLOfFlag);
                //NSLog(@"Current page of flag %ld", pageNumber);

                [aTopic setCurTopicPage:pageNumber];
            }
            else {
                [aTopic setAURLOfFlag:@""];
                [aTopic setATypeOfFlag:@""];
            }

            //Viewed?
            [aTopic setIsViewed:YES];
            HTMLNode * viewedNode = [topicNode findChildWithAttribute:@"class" matchingName:@"sujetCase1" allowPartial:YES];
            HTMLNode * viewedFlagNode = [viewedNode findChildTag:@"img"];
            if (viewedFlagNode) {
                NSString *viewedFlagAlt = [viewedFlagNode getAttributeNamed:@"alt"];
            
                if ([viewedFlagAlt isEqualToString:@"On"]) {
                    [aTopic setIsViewed:NO];
                    countViewed++;
                }
            }

            //aAuthorOrInter
            HTMLNode * interNode = [topicNode findChildWithAttribute:@"class" matchingName:@"sujetCase6" allowPartial:YES];
                
            if ([[interNode findChildTag:@"a"] contents]) {
                NSString *aAuthorOrInter = [[NSString alloc] initWithFormat:@"%@", [[interNode findChildTag:@"a"] contents]];
            [aTopic setAAuthorOrInter:aAuthorOrInter];
            }
            else if ([[interNode findChildTag:@"span"] contents]) {
                NSString *aAuthorOrInter = [[NSString alloc] initWithFormat:@"%@", [[interNode findChildTag:@"span"] contents]];
                [aTopic setAAuthorOrInter:aAuthorOrInter];
            }
            else {
                [aTopic setAAuthorOrInter:@""];
            }

            //Author & Url of Last Post & Date
            HTMLNode * lastRepNode = [topicNode findChildWithAttribute:@"class" matchingName:@"sujetCase9" allowPartial:YES];
            HTMLNode * linkLastRepNode = [lastRepNode firstChild];
        
            if ([[linkLastRepNode findChildTag:@"b"] contents]) {
                NSString *aAuthorOfLastPost = [[NSString alloc] initWithFormat:@"%@", [[linkLastRepNode findChildTag:@"b"] contents]];
                [aTopic setAAuthorOfLastPost:aAuthorOfLastPost];
            }
            else {
                [aTopic setAAuthorOfLastPost:@""];
            }
            
            NSString *aURLOfLastPost = [[NSString alloc] initWithString:[linkLastRepNode getAttributeNamed:@"href"]];
            [aTopic setAURLOfLastPost:aURLOfLastPost];
            

            NSString *maDate = [linkLastRepNode contents];
            NSDateFormatter * df = [[NSDateFormatter alloc] init];
            [df setTimeZone:[NSTimeZone timeZoneWithName:@"Europe/Paris"]];
            [df setDateFormat:@"dd-MM-yyyy à HH:mm"];
            aTopic.dDateOfLastPost = [df dateFromString:maDate];
            NSTimeInterval secondsBetween = [nowTopic timeIntervalSinceDate:aTopic.dDateOfLastPost];
            int numberMinutes = secondsBetween / 60;
            int numberHours = secondsBetween / 3600;
            if (secondsBetween < 0)
            {
                [aTopic setADateOfLastPost:[maDate substringFromIndex:13]];
            }
            else if (numberMinutes == 0)
            {
                [aTopic setADateOfLastPost:@"il y a 1 min"];
            }
            else if (numberMinutes >= 1 && numberMinutes < 60)
            {
                [aTopic setADateOfLastPost:[NSString stringWithFormat:@"il y a %d min",numberMinutes]];
            }
            else if (secondsBetween >= 3600 && secondsBetween < 24*3600)
            {
                [aTopic setADateOfLastPost:[NSString stringWithFormat:@"il y a %d h",numberHours]];
            }
            else
            {
            [aTopic setADateOfLastPost:[NSString stringWithFormat:@"%@/%@/%@", [maDate substringWithRange:NSMakeRange(0, 2)]
                                  , [maDate substringWithRange:NSMakeRange(3, 2)]
                                  , [maDate substringWithRange:NSMakeRange(8, 2)]]];
            }

            //URL of Last Page & maxPage
            HTMLNode * topicLastPageNode = [[topicNode findChildWithAttribute:@"class" matchingName:@"sujetCase4" allowPartial:NO] findChildTag:@"a"];
            if (topicLastPageNode) {
                NSString *aURLOfLastPage = [[NSString alloc] initWithString:[topicLastPageNode getAttributeNamed:@"href"]];
                [aTopic setAURLOfLastPage:aURLOfLastPage];
            [aTopic setMaxTopicPage:[[topicLastPageNode contents] intValue]];

            }
            else {
                [aTopic setAURLOfLastPage:[aTopic aURL]];
                [aTopic setMaxTopicPage:1];

            }
            
            [self.arrayNewData addObject:aTopic];
        }
    }
    
    if (self.status != kNoResults) {
        NSDictionary *notif = [NSDictionary dictionaryWithObjectsAndKeys:[NSNumber numberWithInt:kComplete], @"status", nil];
        [[NSNotificationCenter defaultCenter] postNotificationName:kStatusChangedNotification object:self userInfo:notif];
    }
}

- (void)cancelFetchContent
{
    [request cancel];
    self.searchVisible = NO;
    NSLog(@"BUTTON magnifyingglass");
    
    // Mettre à jour l'icône du bouton
    self.navigationItem.rightBarButtonItem = [[UIBarButtonItem alloc]
        initWithImage:[UIImage systemImageNamed:@"magnifyingglass"]
        style:UIBarButtonItemStylePlain
        target:self
        action:@selector(toggleSearchFields)];
}


/*
- (void)parser:(NSXMLParser *)parser parseErrorOccurred:(NSError *)parseError {
	NSString * errorString = [NSString stringWithFormat:@"Unable to download story feed from web site (Error code %i )", [parseError code]];
	NSLog(@"error parsing XML: %@", errorString);
	NSLog(@"ERROR XML: %@", parseError);
	
	UIAlertView * errorAlert = [[UIAlertView alloc] initWithTitle:@"Error loading content" message:errorString delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil];
	[errorAlert show];
}

- (void)parser:(NSXMLParser *)parser didStartElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName attributes:(NSDictionary *)attributeDict{			
    //NSLog(@"found this element: %@", elementName);
	currentElement = [elementName copy];
	if ([elementName isEqualToString:@"R"]) {
		// clear out our story item caches...
		item = [[NSMutableDictionary alloc] init];
		currentTitle = [[NSMutableString alloc] init];
		currentDate = [[NSMutableString alloc] init];
		currentSummary = [[NSMutableString alloc] init];
		currentLink = [[NSMutableString alloc] init];
	}
	
}

- (void)parser:(NSXMLParser *)parser didEndElement:(NSString *)elementName namespaceURI:(NSString *)namespaceURI qualifiedName:(NSString *)qName{     
	//NSLog(@"ended element: %@", elementName);
	if ([elementName isEqualToString:@"R"]) {
		// save values to an item, then store that item into the array...
		
		NSString *pattern = @"<(.|\n)*?>";

		currentTitle = (NSMutableString *)[currentTitle stringByDecodingXMLEntities];
		[item setObject:[[currentTitle stringByReplacingOccurrencesOfString:@"amp;" withString:@""] stringByReplacingOccurrencesOfRegex:pattern withString:@""] forKey:@"title"];
		[item setObject:[currentLink stringByReplacingOccurrencesOfString:[k RealForumURL] withString:@""] forKey:@"link"];

		currentSummary = (NSMutableString *)[currentSummary stringByDecodingXMLEntities];
		[item setObject:[[currentSummary stringByReplacingOccurrencesOfString:@"amp;" withString:@""] stringByReplacingOccurrencesOfRegex:pattern withString:@""] forKey:@"summary"];
		[item setObject:currentDate forKey:@"date"];
		

        NSString *currentUrl = [[item valueForKey:@"link"] copy];
		int pageNumber;
		
        //NSLog(@"currentUrl %@", currentUrl);
        
		NSString *regexString  = @".*page=([^&]+).*";
		NSRange   matchedRange;// = NSMakeRange(NSNotFound, 0UL);
		NSRange   searchRange = NSMakeRange(0, currentUrl.length);
		NSError  *error2        = NULL;
		
		matchedRange = [currentUrl rangeOfRegex:regexString options:RKLNoOptions inRange:searchRange capture:1L error:&error2];
		
		if (matchedRange.location == NSNotFound) {
			NSRange rangeNumPage =  [currentUrl rangeOfCharactersFromSet:[NSCharacterSet decimalDigitCharacterSet] options:NSBackwardsSearch];
            
            if (rangeNumPage.location == NSNotFound) {
                return;
            }
            
			pageNumber = [[currentUrl substringWithRange:rangeNumPage] intValue];
		}
		else {
			pageNumber = [[currentUrl substringWithRange:matchedRange] intValue];
			
		}
		
		[item setObject:[NSString stringWithFormat:@"p. %d", pageNumber] forKey:@"page"];
		[stories addObject:[item copy]];
	}
	
}

- (void)parser:(NSXMLParser *)parser foundCharacters:(NSString *)string{
	//NSLog(@"found characters: %@", string);
	// save the characters for the current item...
	if ([currentElement isEqualToString:@"T"]) {
		[currentTitle appendString:string];
	} else if ([currentElement isEqualToString:@"UE"]) {
		[currentLink appendString:string];
	} else if ([currentElement isEqualToString:@"S"]) {
		[currentSummary appendString:string];
	} else if ([currentElement isEqualToString:@"pubDate"]) {
		[currentDate appendString:string];
	}
	
}

- (void)parserDidEndDocument:(NSXMLParser *)parser {
	
	NSLog(@"all done!");
	//NSLog(@"stories array has %d items", [stories count]);
	
	//NSLog(@"stories %@", stories);
	NSMutableArray *tmArr = [[NSMutableArray alloc] init];
	
	for (NSDictionary *story in stories) {
		if ([[story valueForKey:@"link"] rangeOfString:@"/liste_sujet"].location != NSNotFound) {
			[tmArr addObject:story];
			
		}
	}
	
	for (NSDictionary *story in tmArr) {
	
		[stories removeObject:story];
	}
	
	//NSLog(@"stories array has %d items", [stories count]);

	if ([stories count] == 0) {
		[self.maintenanceView setText:@"Aucun résultat"];
		[self.maintenanceView setHidden:NO];
		[self.topicsTableView setHidden:YES];
		[self.loadingView setHidden:YES];
	}
	else {
		[self.maintenanceView setHidden:YES];
		[self.topicsTableView setHidden:NO];
		[self.loadingView setHidden:YES];
	}

	
	
	[self.topicsTableView reloadData];
}
*/
// 3. Action lors du changement de sélection
- (void)segmentedControlChanged:(UISegmentedControl *)sender {
    NSInteger selectedIndex = sender.selectedSegmentIndex;
    NSLog(@"Segment sélectionné : %ld", (long)selectedIndex);
    // Filtrage, changement de catégorie, etc.
}

#pragma mark -
#pragma mark Table view data source

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section
{
    if (tableView == self.topicsTableView) {
        return [NSString stringWithFormat:@" p.%d", [self pageNumber]];
    }
    
    return @"Recherches précédentes";
}

- (CGFloat)tableView:(UITableView *)tableView heightForHeaderInSection:(NSInteger)section {
    NSInteger iSizeTextTopics = [[NSUserDefaults standardUserDefaults] integerForKey:@"size_texct_topics"];
    if (tableView == self.topicsTableView) {
        
        if (self.arrayData.count)
            return HEIGHT_FOR_HEADER_IN_SECTION*iSizeTextTopics/100;
        else
            return 0;
    }
    
    return HEIGHT_FOR_HEADER_IN_SECTION*iSizeTextTopics/100;
}

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
	return 1;
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
            cell = tmpCell;
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
                    [button setBackgroundImage:imageForRedFlag forState:UIControlStateNormal];
                    [button setBackgroundImage:imageForRedFlag forState:UIControlStateHighlighted];
                }
                else if ([[aTopic aTypeOfFlag] isEqualToString:@"blue"]) {
                    [button setBackgroundImage:imageForBlueFlag forState:UIControlStateNormal];
                    [button setBackgroundImage:imageForBlueFlag forState:UIControlStateHighlighted];
                }
                else if ([[aTopic aTypeOfFlag] isEqualToString:@"yellow"]) {
                    [button setBackgroundImage:imageForYellowFlag forState:UIControlStateNormal];
                    [button setBackgroundImage:imageForYellowFlag forState:UIControlStateHighlighted];
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

#pragma mark -
#pragma mark Table view delegate

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    self.pressedIndexPath = indexPath;
    
    NSMutableArray *arrayActionsMessages = [NSMutableArray array];
    
    Topic *aTopic = [self.arrayData objectAtIndex:indexPath.row];
    
    if (aTopic.sLastSearchPostURL.length > 0) {
        [arrayActionsMessages addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"Dernière correspondance", @"lastSearchPostAction", nil] forKeys:[NSArray arrayWithObjects:@"title", @"code", nil]]];
    }
    if (aTopic.aURLOfFlag.length > 0) {
        [arrayActionsMessages addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:@"Drapeau", @"lastSearchPostAction", nil] forKeys:[NSArray arrayWithObjects:@"title", @"code", nil]]];
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
        [topicActionAlert addAction:[UIAlertAction actionWithTitle:@"Annuler" style:UIAlertActionStyleCancel handler:^(UIAlertAction *action) {
            [self dismissViewControllerAnimated:YES completion:nil];
        }]];
    }
    else   {
        /*
        // Required for UIUserInterfaceIdiomPad
        //TODO ipad: self.topicsTableView rectForRowAtIndexPath:indexPath
        // CGPoint longPressLocation = [longPressRecognizer locationInView:self.topicsTableView];
        // self.pressedIndexPath = [[:longPressLocation] copy];

        CGPoint pointLocation = [longPressRecognizer locationInView:self.view];
        CGRect origFrame = CGRectMake( pointLocation.x, pointLocation.y, 1, 1);
        topicActionAlert.popoverPresentationController.sourceView = self.view;
        topicActionAlert.popoverPresentationController.sourceRect = origFrame;
        topicActionAlert.popoverPresentationController.backgroundColor = [ThemeColors alertBackgroundColor:[[ThemeManager sharedManager] theme]];*/
    }
    [self presentViewController:topicActionAlert animated:YES completion:nil];
    [[ThemeManager sharedManager] applyThemeToAlertController:topicActionAlert];
}

- (void)pushTopic
{
    if ([[UIDevice currentDevice] userInterfaceIdiom] == UIUserInterfaceIdiomPhone)
    {
        self.navigationItem.backBarButtonItem =
        [[UIBarButtonItem alloc] initWithTitle:@" "
                                         style: UIBarButtonItemStylePlain
                                        target:nil
                                        action:nil];
        
        [self.navigationController pushViewController:messagesTableViewController animated:YES];
    }
    else if (self.detailNavigationViewController)
    {
        messagesTableViewController.navigationItem.leftBarButtonItem = self.detailNavigationViewController.splitViewController.displayModeButtonItem;
        messagesTableViewController.navigationItem.leftItemsSupplementBackButton = YES;
        [self.detailNavigationViewController setViewControllers:[NSMutableArray arrayWithObjects:messagesTableViewController, nil] animated:YES];

        // Close left panel on ipad in portrait mode
        [[HFRplusAppDelegate sharedAppDelegate] hidePrimaryPanelOnIpadForSplitViewController:self.detailNavigationViewController.splitViewController];
    }
}

#pragma mark -
#pragma mark Action delegate

-(void)lastSearchPostAction {
    [self openTopicWithURL:[[self.arrayData objectAtIndex:pressedIndexPath.row] sLastSearchPostURL]];
}

-(void)firstPageAction {
    [self openTopicWithURL:[[self.arrayData objectAtIndex:pressedIndexPath.row] aURL]];
}

-(void)lastPageAction {
    [self openTopicWithURL:[[self.arrayData objectAtIndex:pressedIndexPath.row] aURLOfLastPage]];
}

-(void)lastPostAction {
    [self openTopicWithURL:[[self.arrayData objectAtIndex:pressedIndexPath.row] aURLOfLastPost]];
}

-(void)openTopicWithURL:(NSString*)sURL {
    NSLog(@"Push topic with URL %@", sURL);
    MessagesTableViewController *aView = [[MessagesTableViewController alloc] initWithNibName:@"MessagesTableViewController" bundle:nil andUrl:sURL];
    self.messagesTableViewController = aView;
    
    self.messagesTableViewController.topicName = [[self.arrayData objectAtIndex:pressedIndexPath.row] aTitle];
    self.messagesTableViewController.isViewed = [[self.arrayData objectAtIndex:pressedIndexPath.row] isViewed];
    
    [self pushTopic];
    [self setTopicViewed];
}

-(void)copyLinkAction {
    NSLog(@"copier lien page 1");
    
    UIPasteboard *pasteboard = [UIPasteboard generalPasteboard];
    pasteboard.string = [NSString stringWithFormat:@"%@%@", [k RealForumURL], [[self.arrayData objectAtIndex:pressedIndexPath.row] aURL]];
    
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
        textField.placeholder = [NSString stringWithFormat:@"(numéro entre 1 et %d)", [[self.arrayData objectAtIndex:pressedIndexPath.row] maxTopicPage]];
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
            else if ([[(UITextField *)sender text] intValue] > [[self.arrayData objectAtIndex:pressedIndexPath.row] maxTopicPage]) {
                //NSLog(@"ERROR WAS %d", [[(UITextField *)sender text] intValue]);
                [sender setText:[NSString stringWithFormat:@"%d", [[self.arrayData objectAtIndex:pressedIndexPath.row] maxTopicPage]]];
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
    NSString * newUrl = [[NSString alloc] initWithString:[[self.arrayData objectAtIndex:pressedIndexPath.row] aURL]];
    newUrl = [newUrl stringByReplacingOccurrencesOfString:@"_1.htm" withString:[NSString stringWithFormat:@"_%d.htm", number]];
    newUrl = [newUrl stringByReplacingOccurrencesOfString:@"page=1&" withString:[NSString stringWithFormat:@"page=%d&",number]];
    newUrl = [newUrl stringByRemovingAnchor];
    
    [self openTopicWithURL:[[self.arrayData objectAtIndex:pressedIndexPath.row] aURL]];
}

@end
