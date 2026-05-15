#import "ObjCForumTopicsLoaderWorker.h"

#import "ASIHTTPRequest.h"
#import "Forum.h"
#import "ObjCTopicListParser.h"
#import "Topic.h"

@implementation ObjCForumTopicsLoaderWorker

- (NSString *)normalizedRelativeForumURLString:(NSString *)urlString {
    if (urlString.length == 0) {
        return nil;
    }

    NSString *trimmed = [urlString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
    if (trimmed.length == 0) {
        return nil;
    }

    NSURLComponents *components = [NSURLComponents componentsWithString:trimmed];
    if (!components) {
        return [trimmed hasPrefix:@"/"] ? trimmed : [@"/" stringByAppendingString:trimmed];
    }

    if (components.host.length == 0 && [trimmed hasPrefix:@"/"]) {
        return trimmed;
    }

    NSString *path = components.percentEncodedPath.length > 0 ? components.percentEncodedPath : @"/";
    NSString *relative = components.percentEncodedQuery.length > 0
        ? [NSString stringWithFormat:@"%@?%@", path, components.percentEncodedQuery]
        : path;
    return [relative hasPrefix:@"/"] ? relative : [@"/" stringByAppendingString:relative];
}

- (NSString *)forumURLBySettingOwnTopic:(NSInteger)ownTopic fromURLString:(NSString *)urlString {
    NSString *normalizedURL = [self normalizedRelativeForumURLString:urlString];
    if (normalizedURL.length == 0 || [normalizedURL rangeOfString:@"forum1.php"].location == NSNotFound) {
        return nil;
    }

    NSURLComponents *components = [NSURLComponents componentsWithString:normalizedURL];
    if (!components) {
        return nil;
    }

    NSMutableArray<NSURLQueryItem *> *updatedQueryItems = [NSMutableArray array];
    BOOL hasOwnTopic = NO;
    BOOL hasPage = NO;
    BOOL hasCat = NO;

    for (NSURLQueryItem *item in components.queryItems ?: @[]) {
        if ([item.name isEqualToString:@"owntopic"]) {
            [updatedQueryItems addObject:[NSURLQueryItem queryItemWithName:@"owntopic" value:[NSString stringWithFormat:@"%ld", (long)ownTopic]]];
            hasOwnTopic = YES;
            continue;
        }
        if ([item.name isEqualToString:@"page"]) {
            [updatedQueryItems addObject:[NSURLQueryItem queryItemWithName:@"page" value:@"1"]];
            hasPage = YES;
            continue;
        }
        if ([item.name isEqualToString:@"cat"] && item.value.length > 0) {
            hasCat = YES;
        }
        [updatedQueryItems addObject:item];
    }

    if (!hasCat) {
        return nil;
    }
    if (!hasPage) {
        [updatedQueryItems addObject:[NSURLQueryItem queryItemWithName:@"page" value:@"1"]];
    }
    if (!hasOwnTopic) {
        [updatedQueryItems addObject:[NSURLQueryItem queryItemWithName:@"owntopic" value:[NSString stringWithFormat:@"%ld", (long)ownTopic]]];
    }

    components.queryItems = updatedQueryItems;
    NSString *resolvedURL = components.string ?: normalizedURL;
    return [resolvedURL hasPrefix:@"/"] ? resolvedURL : [@"/" stringByAppendingString:resolvedURL];
}

- (NSString *)forumURLWithCatID:(NSInteger)catID ownTopic:(NSInteger)ownTopic {
    if (catID <= 0) {
        return nil;
    }
    return [NSString stringWithFormat:@"/forum1.php?config=hfr.inc&cat=%ld&page=1&subcat=&owntopic=%ld", (long)catID, (long)ownTopic];
}

- (void)fetchContentForForum:(Forum *)forum
                   flagIndex:(NSInteger)flagIndex
                     pageURL:(NSString *)pageURL
                  completion:(void (^)(NSArray<Topic *> *topics, NSError *error))completion {
    self.forumName = forum.aTitle;

    NSString *normalizedForumURL = [self normalizedRelativeForumURLString:forum.aURL];
    NSString *derivedAllURL = [self forumURLBySettingOwnTopic:0 fromURLString:normalizedForumURL];
    NSString *derivedFavoritesURL = [self forumURLBySettingOwnTopic:3 fromURLString:normalizedForumURL];
    NSString *derivedTrackedURL = [self forumURLBySettingOwnTopic:1 fromURLString:normalizedForumURL];
    NSString *derivedReadURL = [self forumURLBySettingOwnTopic:2 fromURLString:normalizedForumURL];

    NSInteger forumID = forum ? [forum getHFRID] : 0;
    if (forumID <= 0 && forum.aID.length > 0) {
        NSInteger parsedID = 0;
        NSScanner *scanner = [NSScanner scannerWithString:forum.aID];
        [scanner scanInteger:&parsedID];
        forumID = parsedID > 0 ? parsedID : forumID;
    }

    if (derivedAllURL.length > 0) {
        self.forumBaseURL = derivedAllURL;
        self.forumFavorisURL = derivedFavoritesURL ?: derivedAllURL;
        self.forumFlag1URL = derivedTrackedURL ?: derivedAllURL;
        self.forumFlag0URL = derivedReadURL ?: derivedAllURL;
    } else if (forumID > 0) {
        self.forumBaseURL = [self forumURLWithCatID:forumID ownTopic:0];
        self.forumFavorisURL = [self forumURLWithCatID:forumID ownTopic:3];
        self.forumFlag1URL = [self forumURLWithCatID:forumID ownTopic:1];
        self.forumFlag0URL = [self forumURLWithCatID:forumID ownTopic:2];
    } else {
        self.forumBaseURL = normalizedForumURL;
        self.forumFavorisURL = self.forumBaseURL;
        self.forumFlag1URL = self.forumBaseURL;
        self.forumFlag0URL = self.forumBaseURL;
    }

    switch (flagIndex) {
        case 1:
            self.currentUrl = self.forumFavorisURL ?: self.forumBaseURL;
            break;
        case 2:
            self.currentUrl = self.forumFlag1URL ?: self.forumBaseURL;
            break;
        case 3:
            self.currentUrl = self.forumFlag0URL ?: self.forumBaseURL;
            break;
        default:
            self.currentUrl = self.forumBaseURL;
            break;
    }

    NSString *normalizedPageURL = [self normalizedRelativeForumURLString:pageURL];
    if (normalizedPageURL.length > 0) {
        self.currentUrl = normalizedPageURL;
    }

    self.firstPageNumber = 1;
    self.lastPageNumber = 1;
    self.firstPageUrl = nil;
    self.lastPageUrl = nil;
    self.nextPageUrl = nil;
    self.previousPageUrl = nil;
    self.completion = completion;
    [self fetchContentTrigger];
}

- (void)fetchContentComplete:(ASIHTTPRequest *)theRequest {
    if (theRequest != self.request) {
        return;
    }

    ObjCTopicListParsingResult *result = [[[ObjCTopicListParser alloc] init] parseData:[theRequest responseData] currentURL:self.currentUrl];
    [self applyTopicListParsingResult:result];
    self.arrayData = [result.topics mutableCopy];
    [self cancelFetchContent];

    if (self.completion) {
        NSArray<Topic *> *topics = [self.arrayData copy];
        void (^completionBlock)(NSArray<Topic *> *, NSError *) = self.completion;
        self.completion = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock(topics, nil);
        });
    }
}

- (void)fetchContentFailed:(ASIHTTPRequest *)theRequest {
    if (theRequest != self.request) {
        return;
    }

    NSError *error = theRequest.error ?: [NSError errorWithDomain:@"ObjCForumTopicsLoaderWorker" code:-1 userInfo:nil];
    [self cancelFetchContent];

    if (self.completion) {
        void (^completionBlock)(NSArray<Topic *> *, NSError *) = self.completion;
        self.completion = nil;
        dispatch_async(dispatch_get_main_queue(), ^{
            completionBlock(@[], error);
        });
    }
}

@end
