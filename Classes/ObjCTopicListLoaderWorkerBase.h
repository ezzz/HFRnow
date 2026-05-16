#import <Foundation/Foundation.h>

@class ASIFormDataRequest;
@class ASIHTTPRequest;
@class ObjCTopicListParsingResult;

@interface ObjCTopicListLoaderWorkerBase : NSObject

@property (nonatomic, strong) NSMutableArray *arrayData;
@property (nonatomic, strong) NSMutableArray *arrayNewData;
@property (nonatomic, strong) ASIFormDataRequest *request;
@property (nonatomic, assign) BOOL needToUpdateMP;
@property (nonatomic, strong) NSString *sNewMPNumber;
@property (nonatomic, strong) NSString *forumName;
@property (nonatomic, strong) NSString *forumNewTopicUrl;
@property (nonatomic, strong) NSString *forumBaseURL;
@property (nonatomic, strong) NSString *forumFavorisURL;
@property (nonatomic, strong) NSString *forumFlag1URL;
@property (nonatomic, strong) NSString *forumFlag0URL;
@property (nonatomic, strong) NSString *currentUrl;
@property (nonatomic, strong) NSString *currentCat;
@property (nonatomic, assign) int pageNumber;
@property (nonatomic, assign) int firstPageNumber;
@property (nonatomic, assign) int lastPageNumber;
@property (nonatomic, strong) NSString *firstPageUrl;
@property (nonatomic, strong) NSString *lastPageUrl;
@property (nonatomic, strong) NSString *nextPageUrl;
@property (nonatomic, strong) NSString *previousPageUrl;

- (void)cancelFetchContent;
- (void)fetchContentTrigger;
- (void)fetchContentStarted:(ASIHTTPRequest *)request;
- (void)fetchContentComplete:(ASIHTTPRequest *)request;
- (void)fetchContentFailed:(ASIHTTPRequest *)request;
- (void)applyTopicListParsingResult:(ObjCTopicListParsingResult *)result;

@end
