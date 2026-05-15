#import <Foundation/Foundation.h>

@class Topic;

@interface ObjCTopicListParsingResult : NSObject
@property (nonatomic, strong) NSMutableArray<Topic *> *topics;
@property (nonatomic, strong) NSDictionary *statusInfo;
@property (nonatomic, assign) BOOL needToUpdateMP;
@property (nonatomic, strong) NSString *sNewMPNumber;
@property (nonatomic, strong) NSString *currentUrl;
@property (nonatomic, strong) NSString *currentCat;
@property (nonatomic, strong) NSString *forumNewTopicUrl;
@property (nonatomic, strong) NSString *forumBaseURL;
@property (nonatomic, strong) NSString *forumFavorisURL;
@property (nonatomic, strong) NSString *forumFlag1URL;
@property (nonatomic, strong) NSString *forumFlag0URL;
@property (nonatomic, assign) int pageNumber;
@property (nonatomic, assign) int firstPageNumber;
@property (nonatomic, assign) int lastPageNumber;
@property (nonatomic, strong) NSString *firstPageUrl;
@property (nonatomic, strong) NSString *lastPageUrl;
@property (nonatomic, strong) NSString *nextPageUrl;
@property (nonatomic, strong) NSString *previousPageUrl;
@end

@interface ObjCTopicListParser : NSObject
- (ObjCTopicListParsingResult *)parseData:(NSData *)contentData currentURL:(NSString *)currentURL;
@end
