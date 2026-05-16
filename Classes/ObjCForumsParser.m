#import "ObjCForumsParser.h"

#import "Constants.h"
#import "Forum.h"
#import "HFRplusAppDelegate.h"
#import "HTMLParser.h"
#import "RegexKitLite.h"

@implementation ObjCForumsParser

- (NSArray<Forum *> *)parseForumsFromData:(NSData *)contentData
{
    NSMutableArray<Forum *> *forums = [NSMutableArray array];
    
	HTMLParser * myParser = [[HTMLParser alloc] initWithData:contentData error:NULL];
	HTMLNode * bodyNode = [myParser body];
	
	NSArray *temporaryForumsArray = [bodyNode findChildrenWithAttribute:@"class" matchingName:@"cat" allowPartial:YES];

	if ([[[bodyNode firstChild] tagName] isEqualToString:@"p"]) {
        
        
        NSDictionary *notif = [NSDictionary dictionaryWithObjectsAndKeys:   [NSNumber numberWithInt:kMaintenance], @"status",
                               [[[bodyNode firstChild] contents] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]], @"message", nil];
        
        [[NSNotificationCenter defaultCenter] postNotificationName:kStatusChangedNotification object:self userInfo:notif];


    
		return @[];
	}

    //check if user is logged in
    
    BOOL isLogged = false;
    HTMLNode * hashCheckNode = [bodyNode findChildWithAttribute:@"name" matchingName:@"hash_check" allowPartial:NO];
    if (hashCheckNode && ![[hashCheckNode getAttributeNamed:@"value"] isEqualToString:@""]) {
        //hash = logginé :o
        NSLog(@"login = %d", isLogged);
        isLogged = true;
        HTMLNode *hash_check = [bodyNode findChildWithAttribute:@"name" matchingName:@"hash_check" allowPartial:NO];
        [[HFRplusAppDelegate sharedAppDelegate] setHash_check:[hash_check getAttributeNamed:@"value"]];
    }
    //-- check if user is logged in
    
    NSLog(@"login = %d", isLogged);
    
	for (HTMLNode * forumNode in temporaryForumsArray) {

		if (![[forumNode tagName] isEqualToString:@"tr"]) {
			continue;
		}
		
		NSArray *temporaryForumArray = [forumNode findChildTags:@"td"];


		Forum *aForum = [[Forum alloc] init];
		
		
		//Title
		HTMLNode * topicNode = [temporaryForumArray objectAtIndex:1];		
		NSString *aForumTitle = [[NSString alloc] initWithString:[[[topicNode findChildTag:@"b"] allContents] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
		[aForum setATitle:aForumTitle];

  
		//URL
		NSString *aForumURL = [[NSString alloc] initWithString:[[topicNode findChildWithAttribute:@"class" matchingName:@"cCatTopic" allowPartial:YES] getAttributeNamed:@"href"]];
		
		if ([aForumURL isEqualToString:@"/hfr/AchatsVentes/Hardware/liste_sujet-1.htm"]) {
			[aForum setAURL:@"/hfr/AchatsVentes/liste_sujet-1.htm"];
		}
		else {
			[aForum setAURL:aForumURL];
		}
        
        
        //censure Apple :o
        if (!isLogged && [aForumTitle isEqualToString:@"Apple"]) {
            // bah on fait rien ! :o
        }
        else
        {
            // Sous categories
            NSArray *temporaryCatsArray = [topicNode findChildrenWithAttribute:@"class" matchingName:@"Tableau" allowPartial:NO];
            if ([temporaryCatsArray count] > 0) {
                NSMutableArray *tmpSubCatArray = [[NSMutableArray alloc] init];
                
                Forum *aSubForum = [[Forum alloc] init];
                
                //Title
                [aSubForum setATitle:[aForum aTitle]];
                
                //URL
                [aSubForum setAURL:[aForum aURL]];
                
                [tmpSubCatArray addObject:aSubForum];
                

                
                for (HTMLNode * subForumNode in temporaryCatsArray) {
                    Forum *aSubForum = [[Forum alloc] init];

                    //Title
                    NSString *aSubForumTitle = [[NSString alloc] initWithString:[[subForumNode allContents] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]]];
                    [aSubForum setATitle:aSubForumTitle];

                    //URL
                    NSString *aSubForumURL = [[NSString alloc] initWithString:[subForumNode getAttributeNamed:@"href"]];
                    [aSubForum setAURL:aSubForumURL];
                    
                    if ([aSubForum.aURL isEqualToString:@"/hfr/Programmation/API-Win32/liste_sujet-1.htm"]) {
                        Forum *aSubForum2;
                        NSString *aSubForum2Title;
                        NSString *aSubForum2URL;
                        
                        aSubForum2 = [[Forum alloc] init];
                        
                        //Title
                        aSubForum2Title = @"Divers";
                        [aSubForum2 setATitle:aSubForum2Title];
                        
                        //URL
                        aSubForum2URL = @"/hfr/Programmation/Divers-6/liste_sujet-1.htm";
                        [aSubForum2 setAURL:aSubForum2URL];
                        
                        [tmpSubCatArray addObject:aSubForum2];     
                        
                        
                        aSubForum2 = [[Forum alloc] init];
                        
                        //Title
                        aSubForum2Title = @"ADA";
                        [aSubForum2 setATitle:aSubForum2Title];
                        
                        
                        //URL
                        aSubForum2URL = @"/hfr/Programmation/ADA/liste_sujet-1.htm";
                        [aSubForum2 setAURL:aSubForum2URL];
                        
                        [tmpSubCatArray addObject:aSubForum2];                    
                        
                        
                        aSubForum2 = [[Forum alloc] init];
                        
                        //Title
                        aSubForum2Title = @"Algo";
                        [aSubForum2 setATitle:aSubForum2Title];
                        
                        //URL
                        aSubForum2URL = @"/hfr/Programmation/Algo/liste_sujet-1.htm";
                        [aSubForum2 setAURL:aSubForum2URL];
                        
                        [tmpSubCatArray addObject:aSubForum2];                    
                        
                        
                    }                    
                    
                    [tmpSubCatArray addObject:aSubForum];                

                    if ([aSubForum.aURL isEqualToString:@"/hfr/Hardware/minipc/liste_sujet-1.htm"]) {
                        Forum *aSubForum2= [[Forum alloc] init];
                        
                        //Title
                        NSString *aSubForum2Title = @"Bench";
                        [aSubForum2 setATitle:aSubForum2Title];
                        
                        //URL
                    
                        NSString *aSubForum2URL = @"/hfr/Hardware/Benchs/liste_sujet-1.htm";
                        [aSubForum2 setAURL:aSubForum2URL];
                        
                        [tmpSubCatArray addObject:aSubForum2];     
                        

                    }                
                    
                    if ([aSubForum.aURL isEqualToString:@"/hfr/OverclockingCoolingModding/Mod-elec/liste_sujet-1.htm"]) {
                        Forum *aSubForum2= [[Forum alloc] init];
                        
                        //Title
                        NSString *aSubForum2Title = @"Divers";
                        [aSubForum2 setATitle:aSubForum2Title];
                        
                        //URL
                        NSString *aSubForum2URL = @"/hfr/OverclockingCoolingModding/Divers-8/liste_sujet-1.htm";
                        [aSubForum2 setAURL:aSubForum2URL];
                        
                        [tmpSubCatArray addObject:aSubForum2];     
                        
                        
                    }                 
                    
                    if ([aSubForum.aURL isEqualToString:@"/hfr/Photonumerique/Galerie-Perso/liste_sujet-1.htm"]) {
                        Forum *aSubForum2= [[Forum alloc] init];
                        
                        //Title
                        NSString *aSubForum2Title = @"Divers";
                        [aSubForum2 setATitle:aSubForum2Title];
                        
                        //URL
                        NSString *aSubForum2URL = @"/hfr/Photonumerique/Divers-7/liste_sujet-1.htm";
                        [aSubForum2 setAURL:aSubForum2URL];
                        
                        [tmpSubCatArray addObject:aSubForum2];     
                        
                        
                    }                
                    
                    if ([aSubForum.aURL isEqualToString:@"/hfr/WindowsSoftware/Windows-nt-2k-xp/liste_sujet-1.htm"]) {
                        Forum *aSubForum2= [[Forum alloc] init];
                        
                        //Title
                        NSString *aSubForum2Title = @"Win 9x/Me";
                        [aSubForum2 setATitle:aSubForum2Title];
                        
                        //URL
                        NSString *aSubForum2URL = @"/hfr/WindowsSoftware/Win-9x-me/liste_sujet-1.htm";
                        [aSubForum2 setAURL:aSubForum2URL];
                        
                        [tmpSubCatArray addObject:aSubForum2];     
                        
                        
                    }             

                    if ([aSubForum.aURL isEqualToString:@"/hfr/Programmation/API-Win32/liste_sujet-1.htm"]) {
                        Forum *aSubForum2;
                        NSString *aSubForum2Title;
                        NSString *aSubForum2URL;
                        
                        aSubForum2 = [[Forum alloc] init];
                        
                        //Title
                        aSubForum2Title = @"ASM";
                        [aSubForum2 setATitle:aSubForum2Title];
                        
                        //URL
                        aSubForum2URL = @"/hfr/Programmation/ASM/liste_sujet-1.htm";
                        [aSubForum2 setAURL:aSubForum2URL];
                        
                        [tmpSubCatArray addObject:aSubForum2];     
                        
                        
                        aSubForum2 = [[Forum alloc] init];
                        
                        //Title
                        aSubForum2Title = @"ASP";
                        [aSubForum2 setATitle:aSubForum2Title];
                        
                        //URL
                        aSubForum2URL = @"/hfr/Programmation/ASP/liste_sujet-1.htm";
                        [aSubForum2 setAURL:aSubForum2URL];
                        
                        [tmpSubCatArray addObject:aSubForum2];                    
                        
                        
                        aSubForum2 = [[Forum alloc] init];
                        
                        //Title
                        aSubForum2Title = @"Biblio Links";
                        [aSubForum2 setATitle:aSubForum2Title];
                        
                        //URL
                        aSubForum2URL = @"/hfr/Programmation/BiblioLinks/liste_sujet-1.htm";
                        [aSubForum2 setAURL:aSubForum2URL];
                        
                        [tmpSubCatArray addObject:aSubForum2];                    
                        
                        
                        aSubForum2 = [[Forum alloc] init];
                        
                        //Title
                        aSubForum2Title = @"C";
                        [aSubForum2 setATitle:aSubForum2Title];
                        
                        //URL
                        aSubForum2URL = @"/hfr/Programmation/C/liste_sujet-1.htm";
                        [aSubForum2 setAURL:aSubForum2URL];
                        
                        [tmpSubCatArray addObject:aSubForum2];                    
                        
                        
                    } 
                    
                    if ([aSubForum.aURL isEqualToString:@"/hfr/Programmation/C-2/liste_sujet-1.htm"]) {
                        Forum *aSubForum2= [[Forum alloc] init];
                        
                        //Title
                        NSString *aSubForum2Title = @"C#/.NET managed";
                        [aSubForum2 setATitle:aSubForum2Title];
                        
                        //URL
                        NSString *aSubForum2URL = @"/hfr/Programmation/CNET-managed/liste_sujet-1.htm";
                        [aSubForum2 setAURL:aSubForum2URL];
                        
                        [tmpSubCatArray addObject:aSubForum2];     
                        
                        
                    }

                    if ([aSubForum.aURL isEqualToString:@"/hfr/Programmation/Delphi-Pascal/liste_sujet-1.htm"]) {
                        Forum *aSubForum2= [[Forum alloc] init];
                        
                        //Title
                        NSString *aSubForum2Title = @"Flash/ActionScript";
                        [aSubForum2 setATitle:aSubForum2Title];
                        
                        //URL
                        NSString *aSubForum2URL = @"/hfr/Programmation/Flash-ActionScript/liste_sujet-1.htm";
                        [aSubForum2 setAURL:aSubForum2URL];
                        
                        [tmpSubCatArray addObject:aSubForum2];     
                        
                        
                    }                

                    if ([aSubForum.aURL isEqualToString:@"/hfr/Programmation/Java/liste_sujet-1.htm"]) {
                        Forum *aSubForum2;
                        NSString *aSubForum2Title;
                        NSString *aSubForum2URL;
                        
                        aSubForum2 = [[Forum alloc] init];
                        
                        //Title
                        aSubForum2Title = @"Langages fonctionnels";
                        [aSubForum2 setATitle:aSubForum2Title];
                        
                        //URL
                        aSubForum2URL = @"/hfr/Programmation/Langages-fonctionnels/liste_sujet-1.htm";
                        [aSubForum2 setAURL:aSubForum2URL];
                        
                        [tmpSubCatArray addObject:aSubForum2];     
                        
                        
                        aSubForum2 = [[Forum alloc] init];
                        
                        //Title
                        aSubForum2Title = @"PDA";
                        [aSubForum2 setATitle:aSubForum2Title];
                        
                        //URL
                        aSubForum2URL = @"/hfr/Programmation/PDA/liste_sujet-1.htm";
                        [aSubForum2 setAURL:aSubForum2URL];
                        
                        [tmpSubCatArray addObject:aSubForum2];                    
                        
                        
                        aSubForum2 = [[Forum alloc] init];
                        
                        //Title
                        aSubForum2Title = @"Perl";
                        [aSubForum2 setATitle:aSubForum2Title];
                        
                        //URL
                        aSubForum2URL = @"/hfr/Programmation/Perl/liste_sujet-1.htm";
                        [aSubForum2 setAURL:aSubForum2URL];
                        
                        [tmpSubCatArray addObject:aSubForum2];                    
                        
                        
                    }

                    if ([aSubForum.aURL isEqualToString:@"/hfr/Programmation/PHP/liste_sujet-1.htm"]) {
                        Forum *aSubForum2;
                        NSString *aSubForum2Title;
                        NSString *aSubForum2URL;
                        
                        aSubForum2 = [[Forum alloc] init];
                        
                        //Title
                        aSubForum2Title = @"Python";
                        [aSubForum2 setATitle:aSubForum2Title];
                        
                        //URL
                        aSubForum2URL = @"/hfr/Programmation/Python/liste_sujet-1.htm";
                        [aSubForum2 setAURL:aSubForum2URL];
                        
                        [tmpSubCatArray addObject:aSubForum2];     
                        
                        
                        aSubForum2 = [[Forum alloc] init];
                        
                        //Title
                        aSubForum2Title = @"Ruby/Rails";
                        [aSubForum2 setATitle:aSubForum2Title];
                        
                        //URL
                        aSubForum2URL = @"/hfr/Programmation/Ruby/liste_sujet-1.htm";
                        [aSubForum2 setAURL:aSubForum2URL];
                        
                        [tmpSubCatArray addObject:aSubForum2];                    
                        
                        
                    }

                    if ([aSubForum.aURL isEqualToString:@"/hfr/Programmation/SGBD-SQL/liste_sujet-1.htm"]) {
                        Forum *aSubForum2= [[Forum alloc] init];
                        
                        //Title
                        NSString *aSubForum2Title = @"Shell/Batch";
                        [aSubForum2 setATitle:aSubForum2Title];
                        
                        //URL
                        NSString *aSubForum2URL = @"/hfr/Programmation/Shell-Batch/liste_sujet-1.htm";
                        [aSubForum2 setAURL:aSubForum2URL];
                        
                        [tmpSubCatArray addObject:aSubForum2];     
                        
                        
                    }   
                    
                    if ([aSubForum.aURL isEqualToString:@"/hfr/Programmation/VB-VBA-VBS/liste_sujet-1.htm"]) {
                        Forum *aSubForum2= [[Forum alloc] init];
                        
                        //Title
                        NSString *aSubForum2Title = @"XML/XSL";
                        [aSubForum2 setATitle:aSubForum2Title];
                        
                        //URL
                        NSString *aSubForum2URL = @"/hfr/Programmation/XML-XSL/liste_sujet-1.htm";
                        [aSubForum2 setAURL:aSubForum2URL];
                        
                        [tmpSubCatArray addObject:aSubForum2];     
                        
                        
                    }   
                    
                    if ([aSubForum.aURL isEqualToString:@"/hfr/Graphisme/Arts-traditionnels/liste_sujet-1.htm"]) {
                        Forum *aSubForum2;
                        NSString *aSubForum2Title;
                        NSString *aSubForum2URL;
                        
                        aSubForum2 = [[Forum alloc] init];
                        
                        //Title
                        aSubForum2Title = @"Concours";
                        [aSubForum2 setATitle:aSubForum2Title];
                        
                        //URL
                        aSubForum2URL = @"/hfr/Graphisme/Concours-2/liste_sujet-1.htm";
                        [aSubForum2 setAURL:aSubForum2URL];
                        
                        [tmpSubCatArray addObject:aSubForum2];     
                        
                        
                        aSubForum2 = [[Forum alloc] init];
                        
                        //Title
                        aSubForum2Title = @"Ressources";
                        [aSubForum2 setATitle:aSubForum2Title];
                        
                        //URL
                        aSubForum2URL = @"/hfr/Graphisme/Ressources/liste_sujet-1.htm";
                        [aSubForum2 setAURL:aSubForum2URL];
                        
                        [tmpSubCatArray addObject:aSubForum2];                    
                        
                        
                        aSubForum2 = [[Forum alloc] init];
                        
                        //Title
                        aSubForum2Title = @"Divers";
                        [aSubForum2 setATitle:aSubForum2Title];
                        
                        //URL
                        aSubForum2URL = @"/hfr/Graphisme/Divers-5/liste_sujet-1.htm";
                        [aSubForum2 setAURL:aSubForum2URL];
                        
                        [tmpSubCatArray addObject:aSubForum2];                    
                        
                        
                    }                
                    
                    if ([aSubForum.aURL isEqualToString:@"/hfr/AchatsVentes/Softs-livres/liste_sujet-1.htm"]) {
                        Forum *aSubForum2= [[Forum alloc] init];
                        
                        //Title
                        NSString *aSubForum2Title = @"Divers";
                        [aSubForum2 setATitle:aSubForum2Title];
                        
                        //URL
                        NSString *aSubForum2URL = @"/hfr/AchatsVentes/Divers-4/liste_sujet-1.htm";
                        [aSubForum2 setAURL:aSubForum2URL];
                        
                        [tmpSubCatArray addObject:aSubForum2];     
                        
                        
                    }      
                    
                    if ([aSubForum.aURL isEqualToString:@"/hfr/AchatsVentes/Feedback/liste_sujet-1.htm"]) {
                        Forum *aSubForum2= [[Forum alloc] init];
                        
                        //Title
                        NSString *aSubForum2Title = @"Règles et coutumes";
                        [aSubForum2 setATitle:aSubForum2Title];
                        
                        //URL
                        NSString *aSubForum2URL = @"/hfr/AchatsVentes/Regles-coutumes/liste_sujet-1.htm";
                        [aSubForum2 setAURL:aSubForum2URL];
                        
                        [tmpSubCatArray addObject:aSubForum2];     
                        
                        
                    }                
                    
                    

                    

                }
                
                [aForum setSubCats:tmpSubCatArray];

            }
            //--- Sous categories

            if ([aForumURL rangeOfString:@"cat=prive"].location == NSNotFound) {
                [forums addObject:aForum];
            }
            else {
                NSString *regExMP = @"[^.0-9]+([0-9]{1,})[^.0-9]+";			
                NSString *myMPNumber = [[[topicNode findChildWithAttribute:@"class" matchingName:@"cCatTopic" allowPartial:YES] contents] stringByReplacingOccurrencesOfRegex:regExMP
                                                                      withString:@"$1"];
                
                [[HFRplusAppDelegate sharedAppDelegate] updateMPBadgeWithString:myMPNumber];
            }
        }
        


	}
	
    return [forums copy];
}

@end
