@testable import SwiftHFR
import Testing

/// #1151 (HIG: an alert's buttons name the action, not « Oui » / « Non »): the confirmation alerts that asked a yes/no question.
struct AlertButtonVerbsTests {
    @Test func noConfirmationButtonIsAPlainYesOrNo() {
        let titles = [
            AlertVerbs.deleteMessage, AlertVerbs.prepareModeratorMail, AlertVerbs.revertSeasonalIcon, AlertVerbs.skipMPStorage,
            AlertVerbs.cancel, AlertVerbs.keepIcon
        ]
        #expect(!titles.contains { ["Oui", "Non", "Confirmer", "OK"].contains($0) })
    }

    @Test func eachAlertNamesItsAction() {
        #expect(AlertVerbs.deleteMessage == "Supprimer")
        #expect(AlertVerbs.prepareModeratorMail == "Préparer l’email")
        #expect(AlertVerbs.revertSeasonalIcon == "Revenir")
        #expect(AlertVerbs.keepIcon == "Garder")
        #expect(AlertVerbs.skipMPStorage == "Ne pas créer")
        #expect(AlertVerbs.cancel == "Annuler")
    }
}
