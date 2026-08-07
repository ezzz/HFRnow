#import "ObjCForumSearchWorker.h"

#import "HFRplusAppDelegate.h"
#import "ObjCTopicListParser.h"
#import "Topic.h"
#import "k.h"

#define TIME_OUT_INTERVAL_SEARCH 10

@interface ObjCForumSearchWorker ()

@property (nonatomic, strong) NSURLSession *forumSearchSession;
@property (nonatomic, strong) NSURLSessionDataTask *forumSearchTask;
@property (nonatomic, strong) NSURLSessionDataTask *forumSearchRedirectTask;
@property (nonatomic, copy) void (^forumSearchCompletion)(NSArray<Topic *> *topics, NSDictionary *pageInfo, NSError *error);
@property (nonatomic, assign) NSUInteger forumSearchRequestID;
@property (nonatomic, strong) NSData *dInputPostData;

@end

@implementation ObjCForumSearchWorker

- (void)performForumSearchWithParams:(NSDictionary *)params
                           completion:(void (^)(NSArray<Topic *> *topics, NSDictionary *pageInfo, NSError *error))completion {
    [self beginForumSearchWithCompletion:completion];

    self.currentCat = [self forumSearchStringValue:params[@"cat"] fallback:@"13"];
    [[NSUserDefaults standardUserDefaults] setObject:self.currentCat forKey:@"recherche_categorie"];
    self.dInputPostData = [self forumSearchPostDataForParams:params];

    NSURL *url = [NSURL URLWithString:@"https://forum.hardware.fr/search.php?config=hardwarefr.inc"];
    NSMutableURLRequest *request = [self forumSearchRequestWithURL:url method:@"POST" body:self.dInputPostData];
    NSUInteger requestID = self.forumSearchRequestID;

    __weak typeof(self) weakSelf = self;
    self.forumSearchTask = [self.forumSearchSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || requestID != self.forumSearchRequestID) {
            return;
        }
        if (error) {
            [self finishForumSearchWithTopics:nil pageInfo:nil error:error requestID:requestID];
            return;
        }

        NSString *html = [[NSString alloc] initWithData:data ?: [NSData data] encoding:NSUTF8StringEncoding];
        NSString *redirectURL = [self forumSearchRedirectURLFromHTML:html ?: @""];
        if (redirectURL.length == 0) {
            NSError *redirectError = [NSError errorWithDomain:@"TopicsSearchViewController.search"
                                                         code:-2
                                                     userInfo:@{NSLocalizedDescriptionKey: @"Aucune page de résultats n'a été trouvée."}];
            [self finishForumSearchWithTopics:nil pageInfo:nil error:redirectError requestID:requestID];
            return;
        }

        [self followForumSearchRedirectURL:redirectURL requestID:requestID];
    }];

    [self.forumSearchTask resume];
}

- (void)fetchForumSearchPageURL:(NSString *)urlString
                     completion:(void (^)(NSArray<Topic *> *topics, NSDictionary *pageInfo, NSError *error))completion {
    [self beginForumSearchWithCompletion:completion];

    NSString *absoluteURLString = [self forumSearchAbsoluteURLStringFromString:urlString];
    NSURL *url = [NSURL URLWithString:absoluteURLString];
    if (!url) {
        NSError *error = [NSError errorWithDomain:@"TopicsSearchViewController.search"
                                             code:-3
                                         userInfo:@{NSLocalizedDescriptionKey: @"L'URL de résultats est invalide."}];
        [self finishForumSearchWithTopics:nil pageInfo:nil error:error requestID:self.forumSearchRequestID];
        return;
    }

    self.currentUrl = [self forumSearchRelativeURLStringFromString:absoluteURLString];
    NSMutableURLRequest *request = [self forumSearchRequestWithURL:url method:@"GET" body:nil];
    NSUInteger requestID = self.forumSearchRequestID;

    __weak typeof(self) weakSelf = self;
    self.forumSearchTask = [self.forumSearchSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || requestID != self.forumSearchRequestID) {
            return;
        }
        if (error) {
            [self finishForumSearchWithTopics:nil pageInfo:nil error:error requestID:requestID];
            return;
        }

        [self completeForumSearchWithData:data currentURL:self.currentUrl requestID:requestID];
    }];

    [self.forumSearchTask resume];
}

- (void)cancelForumSearch {
    self.forumSearchRequestID += 1;
    [self.forumSearchTask cancel];
    [self.forumSearchRedirectTask cancel];
    self.forumSearchTask = nil;
    self.forumSearchRedirectTask = nil;
    [self.forumSearchSession invalidateAndCancel];
    self.forumSearchSession = nil;

    void (^completion)(NSArray<Topic *> *, NSDictionary *, NSError *) = self.forumSearchCompletion;
    self.forumSearchCompletion = nil;
    if (completion) {
        NSError *error = [NSError errorWithDomain:NSURLErrorDomain
                                             code:NSURLErrorCancelled
                                         userInfo:@{NSLocalizedDescriptionKey: @"Recherche annulée."}];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(@[], @{}, error);
        });
    }
}

- (void)beginForumSearchWithCompletion:(void (^)(NSArray<Topic *> *topics, NSDictionary *pageInfo, NSError *error))completion {
    [self cancelForumSearch];
    self.forumSearchRequestID += 1;
    self.forumSearchCompletion = completion;
    self.forumSearchSession = [self forumSearchNoCookieSession];
}

- (NSURLSession *)forumSearchNoCookieSession {
    NSURLSessionConfiguration *configuration = [NSURLSessionConfiguration ephemeralSessionConfiguration];
    configuration.HTTPCookieAcceptPolicy = NSHTTPCookieAcceptPolicyNever;
    configuration.HTTPCookieStorage = nil;
    configuration.HTTPShouldSetCookies = NO;
    configuration.requestCachePolicy = NSURLRequestReloadIgnoringLocalCacheData;
    configuration.timeoutIntervalForRequest = TIME_OUT_INTERVAL_SEARCH;
    configuration.timeoutIntervalForResource = TIME_OUT_INTERVAL_SEARCH;
    return [NSURLSession sessionWithConfiguration:configuration];
}

- (NSMutableURLRequest *)forumSearchRequestWithURL:(NSURL *)url method:(NSString *)method body:(NSData *)body {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:url];
    request.HTTPMethod = method;
    request.HTTPShouldHandleCookies = NO;
    request.timeoutInterval = TIME_OUT_INTERVAL_SEARCH;
    [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
    if (body) {
        request.HTTPBody = body;
    }
    return request;
}

- (NSData *)forumSearchPostDataForParams:(NSDictionary *)params {
    NSString *searchInput = [[self forumSearchStringValue:params[@"search"] fallback:@""] lowercaseString];
    NSArray *bannedWords = @[@"jailbreak", @"cydia", @"pengu", @"apple jb"];
    for (NSString *word in bannedWords) {
        if ([searchInput rangeOfString:word].location != NSNotFound) {
            searchInput = @"SSBEb24ndCBXYW50IHRvIExpdmUgb24gVGhpcyBQbGFuZXQgQW55bW9yZQ==";
            break;
        }
    }

    NSMutableDictionary *form = [@{
        @"hash_check": [[HFRplusAppDelegate sharedAppDelegate] hash_check] ?: @"",
        @"cat": [self forumSearchStringValue:params[@"cat"] fallback:@"13"],
        @"search": searchInput,
        @"resSearch": @"200",
        @"orderSearch": @"0",
        @"titre": [self forumSearchStringValue:params[@"titre"] fallback:@"3"],
        @"searchtype": [self forumSearchStringValue:params[@"searchtype"] fallback:@"1"],
        @"pseud": @"",
        @"daterange": [self forumSearchStringValue:params[@"daterange"] fallback:@"2"]
    } mutableCopy];

    if ([form[@"daterange"] isEqualToString:@"1"]) {
        form[@"jour"] = [self forumSearchStringValue:params[@"jour"] fallback:@""];
        form[@"mois"] = [self forumSearchStringValue:params[@"mois"] fallback:@""];
        form[@"annee"] = [self forumSearchStringValue:params[@"annee"] fallback:@""];
    }

    return [[self forumSearchURLEncodedFormString:form] dataUsingEncoding:NSUTF8StringEncoding];
}

- (NSString *)forumSearchURLEncodedFormString:(NSDictionary *)form {
    NSArray *orderedKeys = @[@"hash_check", @"cat", @"search", @"resSearch", @"orderSearch", @"titre", @"searchtype", @"pseud", @"daterange", @"jour", @"mois", @"annee"];
    NSMutableArray *pairs = [[NSMutableArray alloc] init];
    for (NSString *key in orderedKeys) {
        NSString *value = [self forumSearchStringValue:form[key] fallback:nil];
        if (!value) {
            continue;
        }
        NSString *encodedKey = [self forumSearchFormEncodedString:key];
        NSString *encodedValue = [self forumSearchFormEncodedString:value];
        [pairs addObject:[NSString stringWithFormat:@"%@=%@", encodedKey, encodedValue]];
    }
    return [pairs componentsJoinedByString:@"&"];
}

- (NSString *)forumSearchFormEncodedString:(NSString *)string {
    NSMutableCharacterSet *allowedCharacters = [[NSCharacterSet alphanumericCharacterSet] mutableCopy];
    [allowedCharacters addCharactersInString:@"-._*"];
    NSString *encoded = [string stringByAddingPercentEncodingWithAllowedCharacters:allowedCharacters] ?: @"";
    return [encoded stringByReplacingOccurrencesOfString:@"%20" withString:@"+"];
}

- (NSString *)forumSearchStringValue:(id)value fallback:(NSString *)fallback {
    if ([value isKindOfClass:[NSString class]]) {
        return value;
    }
    if ([value respondsToSelector:@selector(stringValue)]) {
        return [value stringValue];
    }
    return fallback;
}

- (void)followForumSearchRedirectURL:(NSString *)urlString requestID:(NSUInteger)requestID {
    NSString *absoluteURLString = [self forumSearchAbsoluteURLStringFromString:urlString];
    self.currentUrl = [self forumSearchRelativeURLStringFromString:absoluteURLString];
    NSURL *url = [NSURL URLWithString:absoluteURLString];
    if (!url) {
        NSError *error = [NSError errorWithDomain:@"TopicsSearchViewController.search"
                                             code:-3
                                         userInfo:@{NSLocalizedDescriptionKey: @"L'URL de résultats est invalide."}];
        [self finishForumSearchWithTopics:nil pageInfo:nil error:error requestID:requestID];
        return;
    }

    NSMutableURLRequest *request = [self forumSearchRequestWithURL:url method:@"POST" body:self.dInputPostData];

    __weak typeof(self) weakSelf = self;
    self.forumSearchRedirectTask = [self.forumSearchSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || requestID != self.forumSearchRequestID) {
            return;
        }
        if (error) {
            [self finishForumSearchWithTopics:nil pageInfo:nil error:error requestID:requestID];
            return;
        }

        [self completeForumSearchWithData:data currentURL:self.currentUrl requestID:requestID];
    }];

    [self.forumSearchRedirectTask resume];
}

- (void)completeForumSearchWithData:(NSData *)data currentURL:(NSString *)currentURL requestID:(NSUInteger)requestID {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (requestID != self.forumSearchRequestID) {
            return;
        }

        self.currentUrl = currentURL;
        ObjCTopicListParsingResult *result = [[[ObjCTopicListParser alloc] init] parseData:data ?: [NSData data] currentURL:currentURL];
        [self applyTopicListParsingResult:result];
        NSArray<Topic *> *topics = [result.topics copy] ?: @[];
        self.arrayData = [NSMutableArray arrayWithArray:topics];

        NSDictionary *pageInfo = [self forumSearchPageInfoWithResultCount:topics.count];
        [self finishForumSearchWithTopics:topics pageInfo:pageInfo error:nil requestID:requestID];
    });
}

- (NSDictionary *)forumSearchPageInfoWithResultCount:(NSUInteger)resultCount {
    NSMutableDictionary *info = [@{
        @"pageNumber": @(self.pageNumber),
        @"firstPageNumber": @(self.firstPageNumber),
        @"lastPageNumber": @(self.lastPageNumber),
        @"resultCount": @(resultCount)
    } mutableCopy];

    [self forumSearchSetString:self.currentUrl forKey:@"currentURL" inDictionary:info];
    [self forumSearchSetString:self.currentCat forKey:@"cat" inDictionary:info];
    [self forumSearchSetString:self.nextPageUrl forKey:@"nextPageURL" inDictionary:info];
    [self forumSearchSetString:self.previousPageUrl forKey:@"previousPageURL" inDictionary:info];
    [self forumSearchSetString:self.firstPageUrl forKey:@"firstPageURL" inDictionary:info];
    [self forumSearchSetString:self.lastPageUrl forKey:@"lastPageURL" inDictionary:info];
    return info;
}

- (void)forumSearchSetString:(NSString *)value forKey:(NSString *)key inDictionary:(NSMutableDictionary *)dictionary {
    if (value.length > 0) {
        dictionary[key] = value;
    }
}

- (void)finishForumSearchWithTopics:(NSArray<Topic *> *)topics
                            pageInfo:(NSDictionary *)pageInfo
                               error:(NSError *)error
                           requestID:(NSUInteger)requestID {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (requestID != self.forumSearchRequestID) {
            return;
        }

        void (^completion)(NSArray<Topic *> *, NSDictionary *, NSError *) = self.forumSearchCompletion;
        self.forumSearchCompletion = nil;
        self.forumSearchTask = nil;
        self.forumSearchRedirectTask = nil;
        [self.forumSearchSession finishTasksAndInvalidate];
        self.forumSearchSession = nil;

        if (completion) {
            completion(topics ?: @[], pageInfo ?: @{}, error);
        }
    });
}

- (NSString *)forumSearchRedirectURLFromHTML:(NSString *)html {
    NSError *error = nil;
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"<meta[^>]*http-equiv=[\"']?refresh[\"']?[^>]*content=[\"']\\d+;\\s*url=([^\"']+)[\"'][^>]*>"
                                                                           options:NSRegularExpressionCaseInsensitive
                                                                             error:&error];
    if (error) {
        return nil;
    }

    NSTextCheckingResult *match = [regex firstMatchInString:html options:0 range:NSMakeRange(0, html.length)];
    if (!match || match.numberOfRanges <= 1) {
        return nil;
    }

    NSString *redirectURL = [html substringWithRange:[match rangeAtIndex:1]];
    return [redirectURL stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
}

- (NSString *)forumSearchAbsoluteURLStringFromString:(NSString *)urlString {
    if ([urlString hasPrefix:@"http://"] || [urlString hasPrefix:@"https://"]) {
        return urlString;
    }
    if ([urlString hasPrefix:@"/"]) {
        return [[k ForumURL] stringByAppendingString:urlString];
    }
    return [[NSString stringWithFormat:@"%@/", [k ForumURL]] stringByAppendingString:urlString ?: @""];
}

- (NSString *)forumSearchRelativeURLStringFromString:(NSString *)urlString {
    NSURL *url = [NSURL URLWithString:urlString];
    if (!url.scheme) {
        return urlString;
    }

    NSString *path = url.path ?: @"";
    NSString *query = url.query.length > 0 ? [NSString stringWithFormat:@"?%@", url.query] : @"";
    NSString *fragment = url.fragment.length > 0 ? [NSString stringWithFormat:@"#%@", url.fragment] : @"";
    return [NSString stringWithFormat:@"%@%@%@", path, query, fragment];
}

@end
