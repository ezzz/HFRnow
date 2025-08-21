//
//  AnalyticsManager.h
//  SuperHFRplus
//
//  Created by Bruno ARENE on 08/08/2025.
//

#import <Foundation/Foundation.h>

@interface AnalyticsManager : NSObject

/// Envoie un événement de changement de réglage à Firebase Analytics
+ (void)logSettingChangeWithName:(NSString *)settingName value:(NSString *)settingValue;

/// Envoie l'état actuel de plusieurs réglages (par exemple au lancement de l'app)
+ (void)logCurrentSettings:(NSDictionary<NSString *, NSString *> *)settings;

/// Loggue uniquement la première paire clé/valeur d'un dictionnaire
+ (void)logFirstSettingFromDictionary:(NSDictionary<NSString *, id> *)settingsDict;

/// Envoie un événement Firebase générique avec des paramètres
+ (void)logEventWithName:(NSString *)eventName parameters:(nullable NSDictionary<NSString *, id> *)parameters;

@end
