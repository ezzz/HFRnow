#import "ObjCTopicPageWorker.h"

#import "ASIHTTPRequest+Tools.h"
#import "Constants.h"
#import "HTMLParser.h"
#import "ObjCMessageActionsBuilder.h"
#import "ObjCTopicHTMLRenderContext.h"
#import "ObjCTopicHTMLRenderer.h"
#import "ObjCTopicMessageContentBuilder.h"
#import "ObjCTopicMessageContentResult.h"
#import "ParseMessagesOperation.h"
#import "RegexKitLite.h"
#import "k.h"

@interface ObjCTopicPageWorker ()
@property (nonatomic, strong) ASIHTTPRequest *request;
@property (nonatomic, copy) void (^completion)(NSString *, NSString *, NSNumber *, NSNumber *, NSError *);
@property (nonatomic, strong) NSArray *items;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *inputData;
@property (nonatomic, copy) NSString *currentURL;
@property (nonatomic, copy) NSString *topicAnswerURL;
@property (nonatomic, copy) NSString *anchor;
@property (nonatomic, assign) BOOL separatorRequested;
@property (nonatomic, assign) BOOL unreadable;
@property (nonatomic, readwrite) BOOL swiftHasPoll;
@property (nonatomic, readwrite) BOOL swiftPollIsNewVote;
@property (nonatomic, copy, readwrite) NSString *swiftPollHTML;
@property (nonatomic, copy, readwrite) NSDictionary<NSString *, NSString *> *swiftSearchInputData;
@end

@implementation ObjCTopicPageWorker

- (instancetype)init {
    self = [super init];
    if (self) {
        _inputData = [NSMutableDictionary dictionary];
        _items = @[];
        _swiftSearchInputData = @{};
    }
    return self;
}

- (void)cancelFetchContent {
    [self.request cancel];
    self.request = nil;
}

- (void)fetchContentForTopicURL:(NSString *)topicURL
                         anchor:(NSString *)anchor
                     completion:(void (^)(NSString *, NSString *, NSNumber *, NSNumber *, NSError *))completion {
    [self cancelFetchContent];
    self.completion = completion;
    self.currentURL = topicURL;
    self.anchor = anchor ?: @"";
    self.separatorRequested = anchor.length > 0;
    NSURL *url = [NSURL URLWithString:[NSString stringWithFormat:@"%@%@", [k ForumURL], topicURL]];
    ASIHTTPRequest *request = [ASIHTTPRequest requestWithURL:url];
    self.request = request;
    request.responseEncoding = NSUTF8StringEncoding;
    __weak typeof(self) weakSelf = self;
    __weak ASIHTTPRequest *weakRequest = request;
    [request setCompletionBlock:^{
        ASIHTTPRequest *strongRequest = weakRequest;
        NSString *effectiveURL = strongRequest.url.absoluteString ?: strongRequest.originalURL.absoluteString;
        [weakSelf handleResponseData:[strongRequest safeResponseData] effectiveURL:effectiveURL];
    }];
    [request setFailedBlock:^{
        [weakSelf finishWithHTML:nil answerURL:nil currentPage:nil maxPage:nil error:weakRequest.error];
    }];
    [request startAsynchronous];
}

- (void)handleResponseData:(NSData *)data effectiveURL:(NSString *)effectiveURL {
    NSError *error = nil;
    HTMLParser *htmlParser = [[HTMLParser alloc] initWithData:data error:&error];
    if (!htmlParser || error) {
        [self finishWithHTML:nil answerURL:nil currentPage:nil maxPage:nil error:error];
        return;
    }
    ParseMessagesOperation *parser = [[ParseMessagesOperation alloc] initWithData:data index:0 reverse:NO delegate:nil];
    [parser parseData:htmlParser];
    self.items = [parser.workingArray copy] ?: @[];
    self._topicName = parser.topicName ?: @"";
    self.sNavigationViewTitle = self._topicName;
    self.currentURL = [self relativeURLFromOriginalURL:effectiveURL fallback:self.currentURL];
    [self parseMetadataFromBody:[htmlParser body] parser:htmlParser];

    NSInteger currentPage = [self pageNumberFromURL:self.currentURL];
    NSInteger maxPage = MAX(parser.iLastPageNumber, 1);
    BOOL isPrivate = [self.inputData[@"cat"] isEqualToString:@"prive"];
    ObjCTopicMessageContentResult *content = [[[ObjCTopicMessageContentBuilder alloc] init]
        buildContentForItems:self.items
               currentAnchor:self.anchor
          separatorRequested:self.separatorRequested
           isPrivateCategory:isPrivate];
    self.anchor = content.resolvedAnchor;
    ObjCTopicHTMLRenderContext *context = [[ObjCTopicHTMLRenderContext alloc] init];
    context.messagesHTML = content.messagesHTML ?: @"";
    context.refreshButtonHTML = @"";
    context.toolbarHTML = @"";
    context.customFontSizeCSS = @"";
    context.searchActive = NO;
    NSString *html = [[[ObjCTopicHTMLRenderer alloc] init] renderHTMLWithContext:context];
    NSString *answerURL = self.topicAnswerURL.length > 0
        ? ([self.topicAnswerURL hasPrefix:@"http"] ? self.topicAnswerURL : [NSString stringWithFormat:@"%@%@", [k ForumURL], self.topicAnswerURL])
        : nil;
    [self finishWithHTML:html answerURL:answerURL currentPage:@(MAX(currentPage, 1)) maxPage:@(maxPage) error:nil];
}

- (void)parseMetadataFromBody:(HTMLNode *)body parser:(HTMLParser *)parser {
    [self.inputData removeAllObjects];
    HTMLNode *fastAnswerNode = [body findChildWithAttribute:@"name" matchingName:@"hop" allowPartial:NO];
    for (HTMLNode *input in [fastAnswerNode findChildrenWithAttribute:@"type" matchingName:@"hidden" allowPartial:YES]) {
        NSString *name = [input getAttributeNamed:@"name"];
        NSString *value = [input getAttributeNamed:@"value"];
        if (name && value) self.inputData[name] = value;
    }
    HTMLNode *answerNode = [body findChildWithAttribute:@"id" matchingName:@"repondre_form" allowPartial:NO];
    self.topicAnswerURL = [[answerNode findChildTag:@"a"] getAttributeNamed:@"href"];
    self.unreadable = [body findChildWithAttribute:@"href" matchingName:@"nonlu" allowPartial:YES] != nil;
    HTMLNode *poll = [body findChildWithAttribute:@"class" matchingName:@"sondage" allowPartial:NO];
    self.swiftHasPoll = poll != nil;
    self.swiftPollIsNewVote = [poll findChildTag:@"input"] != nil;
    self.swiftPollHTML = poll ? rawContentsOfNode([poll _node], [parser _doc]) : nil;
    self.swiftSearchInputData = [self searchInputDataFromBody:body];
}

- (NSDictionary<NSString *, NSString *> *)searchInputDataFromBody:(HTMLNode *)body {
    HTMLNode *search = [body findChildWithAttribute:@"action" matchingName:@"/transsearch.php" allowPartial:NO];
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    NSArray *wanted = @[@"hash_check", @"p", @"post", @"cat", @"firstnum", @"currentnum", @"word", @"spseudo", @"filter"];
    for (HTMLNode *input in [search findChildTags:@"input"]) {
        NSString *name = [input getAttributeNamed:@"name"];
        if (![wanted containsObject:name]) continue;
        BOOL checkbox = [[input getAttributeNamed:@"type"] isEqualToString:@"checkbox"];
        if (checkbox && ![[input getAttributeNamed:@"checked"] isEqualToString:@"checked"]) continue;
        NSString *value = [input getAttributeNamed:@"value"];
        if (name && value) result[name] = value;
    }
    return [result copy];
}

- (NSInteger)pageNumberFromURL:(NSString *)url {
    NSRange range = [url rangeOfRegex:@".*page=([^&]+).*" options:RKLNoOptions inRange:NSMakeRange(0, url.length) capture:1 error:nil];
    if (range.location != NSNotFound) return [[url substringWithRange:range] integerValue];
    NSRange digit = [url rangeOfCharacterFromSet:NSCharacterSet.decimalDigitCharacterSet options:NSBackwardsSearch];
    return digit.location != NSNotFound ? [[url substringWithRange:digit] integerValue] : 1;
}

- (NSString *)relativeURLFromOriginalURL:(NSString *)originalURL fallback:(NSString *)fallback {
    if (originalURL.length == 0) return fallback;
    NSString *base = [k ForumURL];
    return [originalURL hasPrefix:base] ? [originalURL substringFromIndex:base.length] : fallback;
}

- (NSDictionary<NSNumber *, NSDictionary<NSString *,NSString *> *> *)swiftMessageActionsByIndex {
    return [[[ObjCMessageActionsBuilder alloc] init] actionsByIndexForItems:self.items
                                                                  inputData:self.inputData
                                                                  topicName:self._topicName
                                                                 currentURL:self.currentURL
                                                              canBeFavorite:!self.unreadable];
}

- (void)finishWithHTML:(NSString *)html answerURL:(NSString *)answerURL currentPage:(NSNumber *)currentPage maxPage:(NSNumber *)maxPage error:(NSError *)error {
    void (^completion)(NSString *, NSString *, NSNumber *, NSNumber *, NSError *) = self.completion;
    self.completion = nil;
    if (!completion) return;
    dispatch_async(dispatch_get_main_queue(), ^{
        completion(html, answerURL, currentPage, maxPage, error);
    });
}

@end
