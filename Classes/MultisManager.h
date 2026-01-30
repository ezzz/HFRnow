//
//  MultisManager.h
//  HFRplus
//
//  Created by Aynolor on 29/09/18.
//
//

#import <Foundation/Foundation.h>
#import "Constants.h"

@interface MultisManager : NSObject 

@property NSArray* comptes;

+ (id)sharedManager;
- (NSArray *)getComtpes;
- (void)addCompteWithPseudo:(NSString *)pseudo andCookies:(NSArray *)cookies andAvatar:(nullable NSData *)avatar andHash:(nullable NSString *)hash NS_SWIFT_NAME(addCompte(pseudo:cookies:avatar:hash:));
- (void)setPseudoAsMain:(NSString *)pseudo NS_SWIFT_NAME(setPseudo(asMain:));
- (NSDictionary *)getMainCompte;
- (NSString *)getCurrentPseudo;
- (void)deletePseudoAtIndex:(NSInteger)index NS_SWIFT_NAME(deletePseudo(at:));
- (UIImage *)getAvatarForCompte:(NSDictionary *)compte;
- (void)forceCookiesForCompte:(NSDictionary *)compte;
- (void)setHashForCompte:(NSDictionary *)compteToUpdate andHash:(NSString *)hash;
- (void)updateCookies:(NSArray *)cookies;
- (void)updateAllAccounts;
@end
