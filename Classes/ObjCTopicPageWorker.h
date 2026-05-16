#import <Foundation/Foundation.h>

@interface ObjCTopicPageWorker : NSObject

@property (nonatomic, readonly) BOOL swiftHasPoll;
@property (nonatomic, readonly) BOOL swiftPollIsNewVote;
@property (nonatomic, readonly) NSString *swiftPollHTML;
@property (nonatomic, readonly) NSDictionary<NSString *, NSString *> *swiftSearchInputData;
@property (nonatomic, copy) NSString *sNavigationViewTitle;
@property (nonatomic, copy) NSString *sNavigationViewSubTitle;
@property (nonatomic, copy) NSString *_topicName;

- (NSDictionary<NSNumber *, NSDictionary<NSString *, NSString *> *> *)swiftMessageActionsByIndex;
- (void)cancelFetchContent;
- (void)fetchContentForTopicURL:(NSString *)topicURL
                         anchor:(NSString *)anchor
                     completion:(void (^)(NSString *html, NSString *topicAnswerURL, NSNumber *currentPage, NSNumber *maxPage, NSError *error))completion;

@end
