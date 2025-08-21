//
//  AnalyticsManager.m
//  SuperHFRplus
//
//  Created by Bruno ARENE on 08/08/2025.
//

#import "AnalyticsManager.h"
#import <FirebaseAnalytics/FirebaseAnalytics.h>

@implementation AnalyticsManager

+ (void)logSettingChangeWithName:(NSString *)settingName value:(NSString *)settingValue {
    if (!settingName || !settingValue) return;

    [FIRAnalytics logEventWithName:@"setting_change"
                        parameters:@{
                            @"setting_name": settingName,
                            @"setting_value": settingValue
                        }];
}

+ (void)logCurrentSettings:(NSDictionary<NSString *, NSString *> *)settings {
    for (NSString *key in settings) {
        NSString *value = settings[key];
        if (value) {
            [self logSettingChangeWithName:key value:value];
        }
    }
}

+ (void)logFirstSettingFromDictionary:(NSDictionary<NSString *, id> *)settingsDict {
    NSString *firstKey = settingsDict.allKeys.firstObject;
    if (!firstKey) return;

    id value = settingsDict[firstKey];
    NSString *valueString;
    if ([value isKindOfClass:[NSNumber class]]) {
        valueString = [(NSNumber *)value stringValue];
    } else if ([value isKindOfClass:[NSString class]]) {
        valueString = (NSString *)value;
    } else {
        valueString = [value description];
    }

    [self logSettingChangeWithName:firstKey value:valueString];
}

+ (void)logEventWithName:(NSString *)eventName parameters:(nullable NSDictionary<NSString *, id> *)parameters {
    if (!eventName || [eventName length] == 0) return;

    if (parameters) {
        [FIRAnalytics logEventWithName:eventName parameters:parameters];
    } else {
        [FIRAnalytics logEventWithName:eventName parameters:nil];
    }
}

@end
