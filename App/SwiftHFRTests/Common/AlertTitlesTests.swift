@testable import SwiftHFR
import Testing

/// #1175 (HIG › Alerts: a title says what failed or what is asked): the error and question alerts of the app.
struct AlertTitlesTests {
    private let all = [
        AlertTitles.pseudoAddFailed, AlertTitles.pseudoAlreadyListed, AlertTitles.pseudoRemoveFailed, AlertTitles.listResetFailed,
        AlertTitles.iconChangeFailed, AlertTitles.accountSwitchFailed, AlertTitles.accountRemoveFailed,
        AlertTitles.markUnreadFailed, AlertTitles.flagRemoveFailed, AlertTitles.blocklistSyncQuestion, AlertTitles.mpStorageQuestion
    ]

    @Test func noTitleIsTheGenericOneTheIssueNames() {
        #expect(!all.contains { ["Erreur", "Icône", "Action impossible", "Stockage MP"].contains($0) })
    }

    @Test func eachTitleIsDistinct() {
        #expect(Set(all).count == all.count)
    }

    @Test func questionsEndWithAQuestionMarkAndFailuresDoNot() {
        #expect(AlertTitles.blocklistSyncQuestion.hasSuffix(" ?") && AlertTitles.mpStorageQuestion.hasSuffix(" ?"))
        #expect(!AlertTitles.accountSwitchFailed.hasSuffix("?") && !AlertTitles.markUnreadFailed.hasSuffix("?"))
    }

    @Test func eachTitleNamesItsSituation() {
        #expect(AlertTitles.pseudoAddFailed == "Ajout impossible")
        #expect(AlertTitles.pseudoRemoveFailed == "Suppression impossible")
        #expect(AlertTitles.iconChangeFailed == "Changement d’icône impossible")
        #expect(AlertTitles.accountSwitchFailed == "Changement de compte impossible")
        #expect(AlertTitles.blocklistSyncQuestion == "Synchroniser la liste noire ?")
        #expect(AlertTitles.mpStorageQuestion == "Activer le stockage MP ?")
    }
}
