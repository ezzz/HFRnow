@testable import SwiftHFR
import Testing

/// The texts of the iCloud account sync row (#1065): a short name, and the explanation the operator reviewed (#312), unchanged,
/// now shown in an info bubble.
struct AccountSyncMessagesTests {
    @Test func theSwitchHasTheShortName() {
        #expect(AccountSyncMessages.title == "Synchro des comptes dans iCloud")
    }

    /// The text moved from under the switch to the bubble without a change of one character: the operator had reviewed it.
    @Test func theExplanationIsUnchanged() {
        #expect(AccountSyncMessages.explanation == """
            Tes comptes (cookies de session et jeton hash_check, jamais de mot de passe) sont copiés dans ton trousseau \
            iCloud, chiffré de bout en bout par Apple, et apparaissent sur tes autres appareils où l’option est activée. \
            Désactiver l’option retire la copie iCloud sur tous tes appareils ; chaque appareil garde les comptes qui y sont \
            connectés.
            """)
    }

    @Test func theInfoButtonHasItsAccessibilityLabel() {
        #expect(AccountSyncMessages.infoLabel == "À propos de la synchro des comptes")
    }
}
