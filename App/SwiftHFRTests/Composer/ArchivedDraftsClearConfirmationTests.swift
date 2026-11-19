@testable import SwiftHFR
import Testing

/// #1179: "Vider" deletes every archived draft of the topic at once, so it asks first (HIG: a destructive action is confirmed,
/// its button names the action). Legacy `AnswerView.swift:1936-1941` @ 87fe0d1c deleted without asking: a deliberate difference.
struct ArchivedDraftsClearConfirmationTests {
    @Test func theConfirmationNamesTheActionAndCannotBeMistakenForTheToolbarButton() {
        #expect(ArchivedDraftsFormat.clearConfirmTitle == "Supprimer les brouillons")
        #expect(ArchivedDraftsFormat.clearConfirmTitle != "Vider")
    }

    @Test(arguments: [
        (1, "Le brouillon archivé de ce topic sera supprimé."),
        (3, "Les 3 brouillons archivés de ce topic seront supprimés.")
    ])
    func theMessageCountsWhatWillBeDeleted(count: Int, expected: String) {
        #expect(ArchivedDraftsFormat.clearConfirmMessage(count: count) == expected)
    }
}
