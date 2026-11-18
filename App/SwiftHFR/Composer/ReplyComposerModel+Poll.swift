import Foundation
import HFRClient
import HFRModels

// Port of HFRswift/Swift/MainWindow.swift:892 and HFRswift/Swift/MessagesView.swift:5434 (`offersPollConfiguration`) @ 87fe0d1c
// (GAP-099). Differences: not on a private thread's first post, whose form never holds the poll block (`R43a`).
extension ReplyComposerModel {
    /// The sheet shows the poll row: a new topic, or the edit of a public topic's first post (its title is editable).
    var showsPoll: Bool {
        if isNewTopic { return true }
        guard case .edit(let edit) = target, prefill?.subject != nil else { return false }
        return edit.topic.category != .privateMessages
    }

    /// The user saved the poll sheet: the poll goes out with the message, when the form allows one.
    func set(poll newDraft: PollDraft) {
        guard showsPoll, canEdit, poll.set(newDraft) else { return }
        clearErrorUnlessMayHavePosted()
    }

    /// "Retirer": the message goes out without a poll.
    func removePoll() {
        guard canEdit else { return }
        poll.remove()
        clearErrorUnlessMayHavePosted()
    }
}
