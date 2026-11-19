import Observation

/// The « Vider » confirmation of the archived-drafts sheet (#1179): asking only raises the question; the archive is emptied by
/// `confirm`, so a tap on « Vider » alone deletes nothing. Its own object so the rule is testable without rendering the sheet.
@MainActor
@Observable
final class ArchivedClearConfirmation {
    /// The confirmation is showing. SwiftUI clears it (through the dialog's binding) before a dialog button's action runs
    /// (AGENTS.md §11, LOT-087), so the decision never reads it: `isRequested` carries it.
    var isAsking = false
    /// « Vider » was tapped and neither answer came yet.
    private(set) var isRequested = false

    /// « Vider » was tapped.
    func request() {
        isRequested = true
        isAsking = true
    }

    /// « Annuler »: nothing is deleted.
    func cancel() {
        isRequested = false
        isAsking = false
    }

    /// « Supprimer les brouillons »: deletes every archived draft of the topic, only after a request.
    func confirm(discardingIn model: ReplyComposerModel) async {
        guard isRequested else { return }
        isRequested = false
        isAsking = false
        await model.discardAllArchived()
    }
}
