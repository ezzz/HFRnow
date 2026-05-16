//
//  FilterPostsQuotes.h
//  SuperHFRplus
//
//  Created by ezzz on 05/04/2020.
//

#import "Topic.h"
#import "ASIHTTPRequest.h"

@class Topic;
#if !APP_SWIFT
@class FavoritesTableViewController, MessagesTableViewController;
#endif

@interface FilterPostsQuotes : NSObject
{
}

@property ASIHTTPRequest *request;
@property NSArray* arrData;
@property Topic* topic;
@property int iStartPage, iLastPageLoaded;
@property BOOL bIsFinished;
@property BOOL bShowPostsRequired, stopRequired;

@property (nonatomic, strong) UIAlertController *alertProgress;
@property (nonatomic, strong) UIProgressView *progressView;
#if !APP_SWIFT
@property (nonatomic, strong) FavoritesTableViewController* favoriteVC;
#endif
#if !APP_SWIFT
@property (nonatomic, strong) MessagesTableViewController* messagesTableVC;
#endif

//+ (FilterPostsQuotes *)shared;

#if !APP_SWIFT
- (void)checkPostsAndQuotesForTopic:(Topic *)topic andVC:(FavoritesTableViewController*)vc;
- (void)checkPostsAndQuotesForAllTopics:(NSArray *)arrTopics andVC:(FavoritesTableViewController*)vc;
#endif

#if !APP_SWIFT
- (void)checkNextPostsAndQuotesWithVC:(MessagesTableViewController*) vc;
#endif

- (void)fetchContentForTopic:(Topic*)topic;
- (void)fetchContentForTopic:(Topic*)topic startPage:(int)iStartPage;

- (void)fetchFilteredPostsForTopic:(Topic * _Nonnull)topic
                          startPage:(NSNumber * _Nullable)startPage
                           progress:(void (^ _Nullable)(NSNumber * _Nonnull currentPage, NSNumber * _Nonnull maxPage, NSNumber * _Nonnull resultCount))progress
                         completion:(void (^ _Nonnull)(NSArray * _Nullable items, NSNumber * _Nullable startPage, NSNumber * _Nullable endPage, NSNumber * _Nonnull finished, NSError * _Nullable error))completion;

- (void)cancelSwiftFiltering;

@end
