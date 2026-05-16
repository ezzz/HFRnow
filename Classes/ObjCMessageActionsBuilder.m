#import "ObjCMessageActionsBuilder.h"

#import "LinkItem.h"
#import "RangeOfCharacters.h"
#import "k.h"

@implementation ObjCMessageActionsBuilder

- (NSDictionary<NSNumber *,NSDictionary<NSString *,NSString *> *> *)actionsByIndexForItems:(NSArray *)items
                                                                                  inputData:(NSDictionary<NSString *,NSString *> *)inputData
                                                                                  topicName:(NSString *)topicName
                                                                                 currentURL:(NSString *)currentURL
                                                                              canBeFavorite:(BOOL)canBeFavorite {
    NSMutableDictionary *actionsByIndex = [NSMutableDictionary dictionary];
    NSString *forumBaseURL = [k ForumURL].length > 0 ? [k ForumURL] : @"https://forum.hardware.fr";
    NSString *realForumBaseURL = [k RealForumURL].length > 0 ? [k RealForumURL] : forumBaseURL;
    BOOL isPrivateCategory = [inputData[@"cat"] isEqualToString:@"prive"];
    BOOL canBookmark = [[NSUserDefaults standardUserDefaults] boolForKey:@"mpstorage_active"] && !isPrivateCategory;
    BOOL canAQ = !isPrivateCategory;
    NSString *topicID = [inputData[@"post"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *topicCategory = [inputData[@"cat"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *trimmedTopicTitle = [topicName stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];

    for (NSUInteger index = 0; index < items.count; index++) {
        id candidate = items[index];
        if (![candidate isKindOfClass:LinkItem.class]) {
            continue;
        }
        LinkItem *item = candidate;
        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        [self setValue:[self absoluteDecodedURL:item.urlQuote forumBaseURL:forumBaseURL] forKey:@"quoteURL" inEntry:entry];
        [self setValue:[self absoluteURL:item.urlProfil forumBaseURL:forumBaseURL] forKey:@"profileURL" inEntry:entry];
        [self setValue:[self absoluteURL:item.MPUrl forumBaseURL:forumBaseURL] forKey:@"privateMessageURL" inEntry:entry];
        [self setValue:[item.imageUI stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] forKey:@"avatarImagePath" inEntry:entry];
        [self setValue:[self absoluteURL:item.addFlagUrl forumBaseURL:forumBaseURL] forKey:@"favoriteURL" inEntry:entry];
        [self setValue:[self absoluteURL:item.urlAlert forumBaseURL:forumBaseURL] forKey:@"alertURL" inEntry:entry];

        NSString *editURL = [self absoluteDecodedURL:item.urlEdit forumBaseURL:forumBaseURL];
        BOOL canDelete = NO;
        if (editURL.length > 0) {
            entry[@"isOwnMessage"] = @"1";
            entry[@"editURL"] = editURL;
            canDelete = index > 0;
        } else {
            entry[@"isOwnMessage"] = @"0";
        }
        [self setValue:item.quoteJS forKey:@"quoteJS" inEntry:entry];
        [self setValue:item.name forKey:@"authorName" inEntry:entry];
        [self setValue:item.postID forKey:@"postID" inEntry:entry];
        [self setValue:[self permalinkURLForPostID:item.postID itemURL:item.url currentURL:currentURL baseForum:realForumBaseURL] forKey:@"permalinkURL" inEntry:entry];
        entry[@"canBeFavorite"] = canBeFavorite ? @"1" : @"0";
        entry[@"isPrivateCategory"] = isPrivateCategory ? @"1" : @"0";
        entry[@"canAQ"] = canAQ ? @"1" : @"0";
        entry[@"canBookmark"] = canBookmark ? @"1" : @"0";
        entry[@"canDelete"] = canDelete ? @"1" : @"0";
        [self setValue:topicID forKey:@"topicID" inEntry:entry];
        [self setValue:topicCategory forKey:@"topicCategory" inEntry:entry];
        [self setValue:trimmedTopicTitle forKey:@"topicTitle" inEntry:entry];
        actionsByIndex[@((NSInteger)index)] = [entry copy];
    }
    return [actionsByIndex copy];
}

- (void)setValue:(NSString *)value forKey:(NSString *)key inEntry:(NSMutableDictionary *)entry {
    if (value.length > 0) {
        entry[key] = value;
    }
}

- (NSString *)absoluteURL:(NSString *)rawURL forumBaseURL:(NSString *)forumBaseURL {
    NSString *trimmed = [rawURL stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return nil;
    trimmed = [trimmed stringByReplacingOccurrencesOfString:@"&amp;" withString:@"&"];
    if ([trimmed hasPrefix:@"http://"] || [trimmed hasPrefix:@"https://"]) return trimmed;
    if ([trimmed hasPrefix:@"//"]) return [NSString stringWithFormat:@"https:%@", trimmed];
    if ([trimmed hasPrefix:@"/"]) return [NSString stringWithFormat:@"%@%@", forumBaseURL, trimmed];
    return [NSString stringWithFormat:@"%@/%@", forumBaseURL, trimmed];
}

- (NSString *)absoluteDecodedURL:(NSString *)rawURL forumBaseURL:(NSString *)forumBaseURL {
    NSString *trimmed = [rawURL stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length == 0) return nil;
    NSString *decoded = trimmed;
    BOOL shouldDecode = trimmed.length > 20 && [trimmed rangeOfString:@"/"].location == NSNotFound && [trimmed rangeOfString:@"http"].location == NSNotFound;
    if (shouldDecode) {
        @try { decoded = [trimmed decodeSpanUrlFromString]; } @catch (__unused NSException *exception) { decoded = trimmed; }
    }
    return [self absoluteURL:decoded forumBaseURL:forumBaseURL];
}

- (NSString *)permalinkURLForPostID:(NSString *)postID itemURL:(NSString *)itemURL currentURL:(NSString *)currentURL baseForum:(NSString *)baseForum {
    NSString *trimmedPostID = [postID stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmedPostID.length == 0) return nil;
    NSString *trimmedItemURL = [itemURL stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSString *rawURL = trimmedItemURL.length > 0 ? trimmedItemURL : currentURL;
    NSString *absoluteURL = [self absoluteURL:rawURL forumBaseURL:baseForum];
    if (absoluteURL.length == 0) return nil;
    NSRange fragmentRange = [absoluteURL rangeOfString:@"#" options:NSBackwardsSearch];
    if (fragmentRange.location != NSNotFound) {
        absoluteURL = [absoluteURL substringToIndex:fragmentRange.location];
    }
    return [NSString stringWithFormat:@"%@#%@", absoluteURL, trimmedPostID];
}

@end
