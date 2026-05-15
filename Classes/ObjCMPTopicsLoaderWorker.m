#import "ObjCMPTopicsLoaderWorker.h"

#import "Topic.h"

@implementation ObjCMPTopicsLoaderWorker

- (void)fetchContentWithCompletion:(void (^)(NSArray<Topic *> *topics, NSError *error))completion {
    self.forumName = @"Messages";
    self.forumBaseURL = @"/forum1.php?config=hfr.inc&cat=prive&page=1";
    self.currentUrl = self.forumBaseURL;
    self.firstPageNumber = 1;
    self.lastPageNumber = 1;
    self.firstPageUrl = nil;
    self.lastPageUrl = nil;
    self.nextPageUrl = nil;
    self.previousPageUrl = nil;
    self.completion = completion;
    [self fetchContentTrigger];
}

@end
