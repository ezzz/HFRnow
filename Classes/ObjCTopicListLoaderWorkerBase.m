#import "ObjCTopicListLoaderWorkerBase.h"

#import "ASIFormDataRequest.h"
#import "Constants.h"
#import "ObjCTopicListParser.h"
#import "k.h"

@implementation ObjCTopicListLoaderWorkerBase

- (instancetype)init {
    self = [super init];
    if (self) {
        _arrayData = [NSMutableArray array];
        _arrayNewData = [NSMutableArray array];
        _forumNewTopicUrl = @"";
        _firstPageNumber = 1;
        _lastPageNumber = 1;
    }
    return self;
}

- (void)cancelFetchContent {
    [self.request cancel];
    self.request = nil;
}

- (void)fetchContentTrigger {
    if (!self.currentUrl) {
        [self cancelFetchContent];
        return;
    }

    if (self.request && ([self.request isExecuting] || ![self.request isFinished])) {
        [self cancelFetchContent];
    }

    [ASIHTTPRequest setDefaultTimeOutSeconds:kTimeoutMini];
    ASIFormDataRequest *request = [ASIHTTPRequest requestWithURL:[NSURL URLWithString:[NSString stringWithFormat:@"%@%@", [k ForumURL], self.currentUrl]]];
    self.request = request;
    request.delegate = self;
    [request setDidStartSelector:@selector(fetchContentStarted:)];
    [request setDidFinishSelector:@selector(fetchContentComplete:)];
    [request setDidFailSelector:@selector(fetchContentFailed:)];
    [request startAsynchronous];
}

- (void)fetchContentStarted:(ASIHTTPRequest *)request {
}

- (void)fetchContentComplete:(ASIHTTPRequest *)request {
}

- (void)fetchContentFailed:(ASIHTTPRequest *)request {
}

- (void)applyTopicListParsingResult:(ObjCTopicListParsingResult *)result {
    self.needToUpdateMP = result.needToUpdateMP;
    self.sNewMPNumber = result.sNewMPNumber;
    self.currentUrl = result.currentUrl;
    self.currentCat = result.currentCat;
    self.forumNewTopicUrl = result.forumNewTopicUrl;
    self.forumBaseURL = result.forumBaseURL;
    self.forumFavorisURL = result.forumFavorisURL;
    self.forumFlag1URL = result.forumFlag1URL;
    self.forumFlag0URL = result.forumFlag0URL;
    self.pageNumber = result.pageNumber;
    self.firstPageNumber = result.firstPageNumber;
    self.lastPageNumber = result.lastPageNumber;
    self.firstPageUrl = result.firstPageUrl;
    self.lastPageUrl = result.lastPageUrl;
    self.nextPageUrl = result.nextPageUrl;
    self.previousPageUrl = result.previousPageUrl;
    self.arrayNewData = [result.topics mutableCopy];
}

@end
