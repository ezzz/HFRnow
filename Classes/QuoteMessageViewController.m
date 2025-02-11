    //
//  QuoteMessageViewController.m
//  HFRplus
//
//  Created by FLK on 17/08/10.
//

#import "HFRplusAppDelegate.h"

#import "QuoteMessageViewController.h"
#import "HTMLParser.h"
#import "Forum.h"
#import "SubCatTableViewController.h"
#import "RegexKitLite.h"
#import "ThemeColors.h"
#import "ThemeManager.h"
#import "ASIHTTPRequest+Tools.h"
#import "SmileyCache.h"
#import "SmileyViewController.h"


@implementation QuoteMessageViewController
@synthesize urlQuote;
@synthesize subcatArray, actionSheet, catButton, textQuote, boldQuote;
- (void)cancelFetchContent
{
	[self.request cancel];
    [self setRequest:nil];
}

- (void)fetchContent
{
	//NSLog(@"======== fetchContent");
	[ASIHTTPRequest setDefaultTimeOutSeconds:kTimeoutMini];
	
	[self setRequest:[ASIHTTPRequest requestWithURL:[NSURL URLWithString:[self.urlQuote lowercaseString]]]];
	[request setDelegate:self];
	
	[request setDidStartSelector:@selector(fetchContentStarted:)];
	[request setDidFinishSelector:@selector(fetchContentComplete:)];
	[request setDidFailSelector:@selector(fetchContentFailed:)];
	
	[self.accessoryView setHidden:YES];
	[self.loadingView setHidden:NO];
	
	[request startAsynchronous];
}

- (void)fetchContentStarted:(ASIHTTPRequest *)theRequest
{
		//started
}

- (void)fetchContentComplete:(ASIHTTPRequest *)theRequest
{
	
	[self.arrayInputData removeAllObjects];
	
	[self loadDataInTableView:[request safeResponseData]];

	[self.accessoryView setHidden:NO];
	[self.loadingView setHidden:YES];
	
	[self setupResponder];
	//NSLog(@"======== fetchContentComplete");
    [self cancelFetchContent];
}

- (void)fetchContentFailed:(ASIHTTPRequest *)theRequest
{
	[self.loadingView setHidden:YES];

    // Popup retry
    UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Ooops !"  message:[theRequest.error localizedDescription]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction* actionCancel = [UIAlertAction actionWithTitle:@"Annuler" style:UIAlertActionStyleCancel
                                                         handler:^(UIAlertAction * action) { [self cancelFetchContent]; }];
    UIAlertAction* actionRetry = [UIAlertAction actionWithTitle:@"Réessayer" style:UIAlertActionStyleDefault
                                                        handler:^(UIAlertAction * action) { [self fetchContent]; }];
    [alert addAction:actionCancel];
    [alert addAction:actionRetry];
    
    [self presentViewController:alert animated:YES completion:nil];
    [[ThemeManager sharedManager] applyThemeToAlertController:alert];
}

 // The designated initializer.  Override if you create the controller programmatically and want to perform customization that is not appropriate for viewDidLoad.
- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil {    
    if ((self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil])) {
        // Custom initialization
		self.subcatArray = [[NSMutableArray alloc] init];
		self.title = @"Répondre";
    }
    return self;
}


/*
// Implement loadView to create a view hierarchy programmatically, without using a nib.
- (void)loadView {
}
*/
- (void)viewDidLoad {
	[super viewDidLoad];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(loadSubCat) name:@"CatSelected" object:nil];
    
	[self fetchContent];
}

// Implement viewDidLoad to do additional setup after loading the view, typically from a nib.
-(void)loadDataInTableView:(NSData *)contentData {
	//[NSURL URLWithString:[self.urlQuote lowercaseString]]
	//NSDate *thenT = [NSDate date]; // Create a current date

	NSError * error = nil;
	//HTMLParser * myParser = [[HTMLParser alloc] initWithContentsOfURL:[NSURL URLWithString:[self.urlQuote lowercaseString]] error:&error];
	HTMLParser * myParser = [[HTMLParser alloc] initWithData:contentData error:&error];
	//NSLog(@"error %@", error);
	//NSDate *then0 = [NSDate date]; // Create a current date

	HTMLNode * bodyNode = [myParser body]; //Find the body tag
		
    // check if user is logged in
    BOOL isLogged = false;
    HTMLNode * hashCheckNode = [bodyNode findChildWithAttribute:@"name" matchingName:@"hash_check" allowPartial:NO];
    if (hashCheckNode && ![[hashCheckNode getAttributeNamed:@"value"] isEqualToString:@""]) {
        //hash = logginé :o
        isLogged = true;
    }
    //username
    NSString *username = @"";
    HTMLNode *usernameNode = [bodyNode findChildWithAttribute:@"name" matchingName:@"pseudo" allowPartial:NO];
    if (usernameNode && ![[usernameNode getAttributeNamed:@"value"] isEqualToString:@""]) {
        //hash = logginé :o
        username = [usernameNode getAttributeNamed:@"value"];
    }
    //-- check if user is logged in
    
    //NSLog(@"FORM login = %d", isLogged);
    //NSLog(@"FORM username = %@", username);
    
    
    // SMILEY PERSO
    HTMLNode * smileyNode = [bodyNode findChildWithAttribute:@"id" matchingName:@"dynamic_smilies" allowPartial:NO];

	NSArray * tmpImageArray =  [smileyNode findChildTags:@"img"];
	
    self.smileyCustom = [[NSString alloc] init];
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *diskCachePath = [[paths objectAtIndex:0] stringByAppendingPathComponent:@"SmileCache"];

    if (![[NSFileManager defaultManager] fileExistsAtPath:diskCachePath])
    {
        //NSLog(@"createDirectoryAtPath");
        [[NSFileManager defaultManager] createDirectoryAtPath:diskCachePath
                                  withIntermediateDirectories:YES
                                                   attributes:nil
                                                        error:NULL];
    }
    else {
        //NSLog(@"pas createDirectoryAtPath");
    }
    
    NSFileManager *fileManager = [[NSFileManager alloc] init];

    //Traitement des smileys (to Array)
    //[self.smileyArray removeAllObjects]; //RaZ
    self.arrSmileyCustom = [[NSMutableArray alloc] init];
    for (HTMLNode * imgNode in tmpImageArray) { //Loop through all the tags
        
        NSString *filename = [[imgNode getAttributeNamed:@"src"] stringByReplacingOccurrencesOfString:@"http://forum-images.hardware.fr/" withString:@""];
        filename = [filename stringByReplacingOccurrencesOfString:@"https://forum-images.hardware.fr/" withString:@""];
        filename = [filename stringByReplacingOccurrencesOfString:@"/" withString:@"-"];
        filename = [filename stringByReplacingOccurrencesOfString:@" " withString:@"-"];
        
        NSString *key = [diskCachePath stringByAppendingPathComponent:filename];
        
        //NSLog(@"url %@", [imgNode getAttributeNamed:@"src"]);
        //NSLog(@"key %@", key);
        
        if (![fileManager fileExistsAtPath:key])
        {
            //NSLog(@"dl %@", key);
            
            [fileManager createFileAtPath:key contents:[NSData dataWithContentsOfURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@", [[imgNode getAttributeNamed:@"src"] stringByAddingPercentEscapesUsingEncoding:NSASCIIStringEncoding]]]] attributes:nil];
        }
        
        
        self.smileyCustom = [self.smileyCustom stringByAppendingFormat:@"<img class=\"smile\" src=\"%@\" alt=\"%@\"/>", key, [imgNode getAttributeNamed:@"alt"]];
        [self.arrSmileyCustom addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:[imgNode getAttributeNamed:@"src"], [imgNode getAttributeNamed:@"alt"], nil] forKeys:[NSArray arrayWithObjects:@"source", @"code", nil]]];
        NSLog(@"Custom smiley:%@ - %@",[imgNode getAttributeNamed:@"alt"],[imgNode getAttributeNamed:@"src"]);
        
        
        //self.smileyCustom = [self.smileyCustom stringByAppendingFormat:@"<img class=\"smile\" src=\"%@\" alt=\"%@\"/>", [imgNode getAttributeNamed:@"src"], [imgNode getAttributeNamed:@"alt"]];
        //[self.smileyArray addObject:[NSDictionary dictionaryWithObjects:[NSArray arrayWithObjects:[imgNode getAttributeNamed:@"src"], [imgNode getAttributeNamed:@"alt"], nil] forKeys:[NSArray arrayWithObjects:@"source", @"code", nil]]];
        
    }

    //NSLog(@"smileyNode %@", rawContentsOfNode([smileyNode _node], [myParser _doc]));
    //NSLog(@"smileyCustom %@", self.smileyCustom);

    [[SmileyCache shared] handleCustomSmileyArray:self.arrSmileyCustom forCollection:self.viewControllerSmileys.collectionViewSmileysFavorites];
    [self.viewControllerSmileys.collectionViewSmileysFavorites reloadData];
    // SMILEY PERSO
    
	HTMLNode * fastAnswerNode = [bodyNode findChildWithAttribute:@"name" matchingName:@"hop" allowPartial:NO];
	
	NSArray *temporaryAllInputArray = [fastAnswerNode findChildTags:@"input"];
	//NSLog(@"inputNode ========== %d", temporaryAllInputArray.count);

	temporaryAllInputArray = [temporaryAllInputArray arrayByAddingObjectsFromArray:[fastAnswerNode findChildTags:@"select"]];
	
	//NSLog(@"inputNode ========== %d", temporaryAllInputArray.count);

	for (HTMLNode * inputallNode in temporaryAllInputArray) { //Loop through all the tags
		//NSLog(@"inputallNode: %@ - value: %@", [inputallNode getAttributeNamed:@"name"], [inputallNode getAttributeNamed:@"value"]);

		if ([inputallNode getAttributeNamed:@"value"] && [inputallNode getAttributeNamed:@"name"]) {
			
			if ([[inputallNode getAttributeNamed:@"name"] isEqualToString:@"MsgIcon"]) {
				if ([[inputallNode getAttributeNamed:@"checked"] isEqualToString:@"checked"]) {
					[self.arrayInputData setObject:[inputallNode getAttributeNamed:@"value"] forKey:[inputallNode getAttributeNamed:@"name"]];
				}

			}
			else if ([[inputallNode getAttributeNamed:@"type"] isEqualToString:@"checkbox"]) {
				if ([[inputallNode getAttributeNamed:@"checked"] isEqualToString:@"checked"]) {
					//NSLog(@"checked");
					[self.arrayInputData setObject:@"1" forKey:[inputallNode getAttributeNamed:@"name"]];
				}
				else {
					//NSLog(@"pas checked");
					[self.arrayInputData setObject:@"0" forKey:[inputallNode getAttributeNamed:@"name"]];
				}

			}
			else {
				[self.arrayInputData setObject:[inputallNode getAttributeNamed:@"value"] forKey:[inputallNode getAttributeNamed:@"name"]];
			}

			
			if ([[inputallNode getAttributeNamed:@"name"] isEqualToString:@"sujet"]) {
				if ([[inputallNode getAttributeNamed:@"type"] isEqualToString:@"hidden"]) {
				}
				else {
					//NSLog(@"Sujet OK");
					self.haveTitle = YES;
				}
			}
			
			if ([[inputallNode getAttributeNamed:@"name"] isEqualToString:@"dest"]) {
				//NSLog(@"haveTohaveTohaveTohaveTohaveTo");
				self.haveTo = YES;
			}
		}		
		else if ([[inputallNode tagName] isEqualToString:@"select"]) {
			
			if ([[inputallNode getAttributeNamed:@"name"] isEqualToString:@"subcat"]) {
				self.haveCategory = YES;
				
				for (HTMLNode * catNode in [inputallNode children]) { //Loop through all the tags
					
					Forum *aForum = [[Forum alloc] init];

					//Title
					NSString *aForumTitle = [[NSString alloc] initWithString:[[catNode allContents] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
					[aForum setATitle:aForumTitle];
					//ID
					NSString *aForumID = [[NSString alloc] initWithString:[[catNode getAttributeNamed:@"value"] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
					[aForum setAID:aForumID];

					[self.subcatArray addObject:aForum];
				}
			}
                    
			//NSLog(@"select");
			HTMLNode *selectedNode = [inputallNode findChildWithAttribute:@"selected" matchingName:@"selected" allowPartial:NO];
			if (selectedNode) {
				//NSLog(@"selectedNode %@ %@", [selectedNode contents], [inputallNode getAttributeNamed:@"name"]);
				[self.arrayInputData setObject:[selectedNode getAttributeNamed:@"value"] forKey:[inputallNode getAttributeNamed:@"name"]];
			}
			else {
				//NSLog(@"pas selected %@ %@", [[inputallNode firstChild] contents], [inputallNode getAttributeNamed:@"name"]);
				[self.arrayInputData setObject:[[inputallNode firstChild] getAttributeNamed:@"value"] forKey:[inputallNode getAttributeNamed:@"name"]];
			}
		}
	}
	
	[super initData];
	
	//EDITOR
    float frameWidth = self.view.frame.size.width;
    
    //NSLog(@"self %f", self.view.frame.size.width);
    
	float originY = 0;
	
	UIView *headerView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, frameWidth, 0)];
    //[headerView setBackgroundColor:[UIColor greenColor]];
    
	headerView.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    
	if (self.haveTo) {
		UITextField *titleLabel = [[UITextField alloc] initWithFrame:CGRectMake(8, originY, 25, 43)];
		titleLabel.text = @"À :";
		titleLabel.backgroundColor = [UIColor clearColor];
		titleLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1];
		titleLabel.font = [UIFont systemFontOfSize:15];
		titleLabel.userInteractionEnabled = NO;
		titleLabel.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
        titleLabel.autocorrectionType = UITextAutocorrectionTypeNo;

		textFieldTo = [[UITextField alloc] initWithFrame:CGRectMake(38, originY, frameWidth - 55, 43)];
        textFieldTo.tag = 1;
		textFieldTo.backgroundColor = [UIColor clearColor];
		textFieldTo.font = [UIFont systemFontOfSize:15];
		textFieldTo.delegate = self;
		textFieldTo.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
		textFieldTo.returnKeyType = UIReturnKeyNext;
		[textFieldTo setText:[self.arrayInputData valueForKey:@"dest"]];
		textFieldTo.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        textFieldTo.keyboardType = UIKeyboardTypeASCIICapable;
        textFieldTo.textColor = [ThemeColors textColor:[[ThemeManager sharedManager] theme]];
        textFieldTo.autocorrectionType = UITextAutocorrectionTypeNo;

		originY += textFieldTo.frame.size.height;
		
		UIView* separator = [[UIView alloc] initWithFrame:CGRectMake(0, originY, frameWidth, 1)];
		separator.backgroundColor = [ThemeColors cellBorderColor:[[ThemeManager sharedManager] theme]];
		separator.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		
		originY += separator.frame.size.height;
		
		[headerView addSubview:titleLabel];
		[headerView addSubview:textFieldTo];
		[headerView addSubview:separator];
		
		
		headerView.frame = CGRectMake(headerView.frame.origin.x, headerView.frame.origin.x, headerView.frame.size.width, originY);	
	}

	if (self.haveTitle) {
		UITextField *titleLabel = [[UITextField alloc] initWithFrame:CGRectMake(8, originY, 45, 43)];
		titleLabel.text = @"Sujet :";
		titleLabel.backgroundColor = [UIColor clearColor];
		titleLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1];
		titleLabel.font = [UIFont systemFontOfSize:15];
		titleLabel.userInteractionEnabled = NO;
		titleLabel.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
		titleLabel.autocorrectionType = UITextAutocorrectionTypeNo;
        
		textFieldTitle = [[UITextField alloc] initWithFrame:CGRectMake(58, originY, frameWidth - 75, 43)];
        textFieldTitle.tag = 2;
		textFieldTitle.backgroundColor = [UIColor clearColor];
		textFieldTitle.font = [UIFont systemFontOfSize:15];
		textFieldTitle.delegate = self;
		textFieldTitle.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
		textFieldTitle.returnKeyType = UIReturnKeyNext;
		[textFieldTitle setText:[self.arrayInputData valueForKey:@"sujet"]];
		textFieldTitle.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        textFieldTitle.keyboardType = UIKeyboardTypeASCIICapable;
        textFieldTitle.textColor = [ThemeColors textColor:[[ThemeManager sharedManager] theme]];
        textFieldTitle.keyboardAppearance = [ThemeColors keyboardAppearance];
        textFieldTitle.autocorrectionType = UITextAutocorrectionTypeNo;

		originY += textFieldTitle.frame.size.height;
		
		UIView* separator = [[UIView alloc] initWithFrame:CGRectMake(0, originY, frameWidth, 1)];
		separator.backgroundColor = [ThemeColors cellBorderColor:[[ThemeManager sharedManager] theme]];
		separator.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		
		originY += separator.frame.size.height;
		
		[headerView addSubview:titleLabel];
		[headerView addSubview:textFieldTitle];
		[headerView addSubview:separator];
		
		headerView.frame = CGRectMake(headerView.frame.origin.x, headerView.frame.origin.x, headerView.frame.size.width, originY);
	}
	
	if (self.haveCategory) {
		UITextField *titleLabel = [[UITextField alloc] initWithFrame:CGRectMake(8, originY, 75, 43)];
		titleLabel.text = @"Catégorie :";
		titleLabel.backgroundColor = [UIColor clearColor];
		titleLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1];
		titleLabel.font = [UIFont systemFontOfSize:15];
        NSLog(@"font %@", titleLabel.font);
        [titleLabel sizeToFit];
        CGRect tmpFrame = titleLabel.frame;
        tmpFrame.size.height = 43.0f;
        
        titleLabel.frame = tmpFrame;
		titleLabel.userInteractionEnabled = NO;
		titleLabel.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
		
		catButton = [UIButton buttonWithType:UIButtonTypeRoundedRect];
		catButton.frame = CGRectMake(8 + titleLabel.frame.size.width + 5, originY + 5, frameWidth - 105, 33);
        
        NSMutableArray* actionList = [[NSMutableArray alloc] init];
		for (Forum *aForum in self.subcatArray) {
            //NSLog(@"FORUM Subcat: %@ / %@", [aForum aID], [aForum aTitle]);
            [actionList addObject:[UIAction actionWithTitle:[aForum aTitle] image:nil identifier:nil  handler:^(__kindof UIAction * _Nonnull action) {
                [self->catButton setTitle:[aForum aTitle] forState:UIControlStateNormal];
                [self->textFieldCat setText:[aForum aID]];
                NSLog(@"FORUM selection %@", self->textFieldCat.text);
                    }]];
		}
        catButton.menu = [UIMenu menuWithChildren:actionList];

        [catButton setContentHorizontalAlignment:UIControlContentHorizontalAlignmentRight];
        [catButton setContentEdgeInsets:UIEdgeInsetsMake(0, 0, 0, 15)];
		catButton.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        
        
        [catButton setTitle:@"Aucune" forState:UIControlStateNormal];
        catButton.showsMenuAsPrimaryAction = YES;
        //catButton.backgroundColor = [UIColor redColor];
        
		textFieldCat = [[UITextField alloc] initWithFrame:CGRectMake(88, originY, 215, 43)];
		textFieldCat.backgroundColor = [UIColor clearColor];
		textFieldCat.font = [UIFont systemFontOfSize:15];
		textFieldCat.delegate = self;
		textFieldCat.contentVerticalAlignment = UIControlContentVerticalAlignmentCenter;
		textFieldCat.keyboardAppearance = UIKeyboardAppearanceAlert;
		textFieldCat.returnKeyType = UIReturnKeyNext;
        textFieldCat.userInteractionEnabled = NO;
		NSLog(@"FORUM CAT %@", [self.arrayInputData valueForKey:@"subcat"]);
		[textFieldCat setText:[self.arrayInputData valueForKey:@"subcat"]];
		textFieldCat.userInteractionEnabled = NO;
		textFieldCat.autoresizingMask = UIViewAutoresizingFlexibleWidth;
        textFieldCat.keyboardType = UIKeyboardTypeASCIICapable;
        textFieldCat.hidden = YES;
        
		originY += textFieldCat.frame.size.height;
		
		UIView* separator = [[UIView alloc] initWithFrame:CGRectMake(0, originY, frameWidth, 1)];
		separator.backgroundColor = [ThemeColors cellBorderColor:[[ThemeManager sharedManager] theme]];
		separator.autoresizingMask = UIViewAutoresizingFlexibleWidth;
		
		originY += separator.frame.size.height;
		
		[headerView addSubview:titleLabel];
		[headerView addSubview:textFieldCat];
		[headerView addSubview:catButton];
		[headerView addSubview:separator];
    }

	headerView.frame = CGRectMake(headerView.frame.origin.x, originY * -1.0f, headerView.frame.size.width, originY);
	[self.textViewPostContent addSubview:headerView];
    self.textViewPostContent.tag = 3;

	self.offsetY = originY * -1.0f;
	self.textViewPostContent.contentInset = UIEdgeInsetsMake(originY, 0.0f, 0.0f, 0.0f);
	self.textViewPostContent.contentOffset = CGPointMake(0.0f, self.offsetY);

	NSString* txtTW = [[fastAnswerNode findChildWithAttribute:@"id" matchingName:@"content_form" allowPartial:NO] contents];
    txtTW = [txtTW stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];

    NSLog(@"txtTW %@", txtTW);
    
    if (self.textQuote.length) {
        NSLog(@"textQuote %@", self.textQuote);
        self.textQuote = [self.textQuote stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
        //Test multiQUOTEMSG
        
        NSString *pattern = @"\\[quotemsg=([0-9]+),([0-9]+),([0-9]+)\\](?s)((|.*?)+)\\[\\/quotemsg\\]";
        NSError *error = NULL;
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:pattern
                                                                               options:NSRegularExpressionDotMatchesLineSeparators
                                                                                 error:&error];
        
        NSLog(@"error %@", error);
        
        NSArray  *capturesArray = NULL;
        NSRange range = NSMakeRange(0, txtTW.length);

        capturesArray = [regex matchesInString:txtTW options:0 range:range];
        NSLog(@"capturesArray: %@", capturesArray);
        
        //NSLog(@"TXT BEFORE==== %@", txtTW);
        
        if (capturesArray.count > 1) {
            NSLog(@"Plusieurs quotemsg, il faut trouver le bon !");
            
            for (NSTextCheckingResult *quoteA in capturesArray) {
                
                NSString *quoteTxt = [txtTW substringWithRange:[quoteA rangeAtIndex:0]];
                NSLog(@"Txt de la quote %@", quoteTxt);
                
                if ([quoteTxt rangeOfString:self.textQuote options:NSCaseInsensitiveSearch].location != NSNotFound) {
                    NSLog(@"Selec trouvée");
                    
                    //case BOLD
                    if (self.boldQuote) {
                        //on laisse le txt du qtemsg et on bold
                        txtTW = [NSString stringWithFormat:@"%@\n", quoteTxt];
                        txtTW = [txtTW stringByReplacingOccurrencesOfString:self.textQuote withString:[NSString stringWithFormat:@"[b]%@[/b]", self.textQuote]];
                    }
                    else {
                        //case EXCLU
                        txtTW = [NSString stringWithFormat:@"[quotemsg=%d,%d,%d]%@[/quotemsg]\n", [[txtTW substringWithRange:[quoteA rangeAtIndex:1]] intValue], [[txtTW substringWithRange:[quoteA rangeAtIndex:2]] intValue], [[txtTW substringWithRange:[quoteA rangeAtIndex:3]] intValue], self.textQuote];
                        //recup le quotemsg et y inserer le msg
                    }
                    break;
                    
                }
                else {
                    NSLog(@"select pas trouvée");
                }
            }
        }
        else if (capturesArray.count == 1) {
            if (self.boldQuote) {
                //on laisse le txt et on bold
                txtTW = [txtTW stringByReplacingOccurrencesOfString:self.textQuote withString:[NSString stringWithFormat:@"[b]%@[/b]", self.textQuote]];
            }
            else {
                //recup le quotemsg et y inserer le msg
                txtTW = [NSString stringWithFormat:@"[quotemsg=%d,%d,%d]%@[/quotemsg]\n", [[txtTW substringWithRange:[capturesArray[0] rangeAtIndex:1]] intValue], [[txtTW substringWithRange:[capturesArray[0] rangeAtIndex:2]] intValue], [[txtTW substringWithRange:[capturesArray[0] rangeAtIndex:3]] intValue], self.textQuote];
            }
        }
        else {
            NSLog(@"On touche RIEN MEC");
        }
    }
    
	[self.textViewPostContent setText:txtTW];
	[self textViewDidChange:self.textViewPostContent];
	NSString *newSubmitForm = [[NSString alloc] initWithFormat:@"%@%@", [k ForumURL], [fastAnswerNode getAttributeNamed:@"action"]];
	[self setFormSubmit:newSubmitForm];	
}

@end
