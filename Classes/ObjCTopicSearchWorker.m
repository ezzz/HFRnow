#import "ObjCTopicSearchWorker.h"

#import "ASIFormDataRequest.h"
#import "Constants.h"
#import "k.h"

@implementation ObjCTopicSearchWorker

- (void)performTopicSearchWithParams:(NSDictionary<NSString *, NSString *> *)params
                          completion:(void (^)(NSString *resultURL, NSError *error))completion {
    if (!completion) {
        return;
    }
    if (!params || params.count == 0) {
        NSError *error = [NSError errorWithDomain:@"ObjCTopicSearchWorker.search"
                                             code:-10
                                         userInfo:@{NSLocalizedDescriptionKey: @"Aucun critère de recherche"}];
        dispatch_async(dispatch_get_main_queue(), ^{
            completion(nil, error);
        });
        return;
    }

    NSURL *searchURL = [NSURL URLWithString:[NSString stringWithFormat:@"%@/transsearch.php", [k ForumURL]]];
    ASIFormDataRequest *searchRequest = [[ASIFormDataRequest alloc] initWithURL:searchURL];
    for (NSString *key in params) {
        NSString *value = params[key];
        if (![key isKindOfClass:[NSString class]] || ![value isKindOfClass:[NSString class]]) {
            continue;
        }
        [searchRequest setPostValue:value forKey:key];
    }
    [searchRequest setShouldRedirect:NO];
    [searchRequest setTimeOutSeconds:kTimeoutMaxi];

    __weak ASIFormDataRequest *weakRequest = searchRequest;
    [searchRequest setCompletionBlock:^{
        __strong ASIFormDataRequest *strongRequest = weakRequest;
        NSString *location = strongRequest.responseHeaders[@"Location"];
        NSError *requestError = strongRequest.error;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (requestError) {
                completion(nil, requestError);
                return;
            }
            if (location.length == 0) {
                NSError *error = [NSError errorWithDomain:@"ObjCTopicSearchWorker.search"
                                                     code:-11
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Aucun résultat n'a été trouvé"}];
                completion(nil, error);
                return;
            }
            completion(location, nil);
        });
    }];
    [searchRequest setFailedBlock:^{
        __strong ASIFormDataRequest *strongRequest = weakRequest;
        NSError *requestError = strongRequest.error;
        dispatch_async(dispatch_get_main_queue(), ^{
            NSError *error = requestError ?: [NSError errorWithDomain:@"ObjCTopicSearchWorker.search"
                                                                 code:-12
                                                             userInfo:@{NSLocalizedDescriptionKey: @"Échec de la recherche"}];
            completion(nil, error);
        });
    }];
    [searchRequest startAsynchronous];
}

@end
