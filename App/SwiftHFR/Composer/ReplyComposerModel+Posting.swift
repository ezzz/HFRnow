import Foundation
import HFRClient

extension ReplyComposerModel {
    /// A new private message: the sheet shows the recipient and subject fields.
    var isNewMessage: Bool {
        if case .newPrivateMessage = target { true } else { false }
    }

    /// A new topic: the sheet shows the subject field and the sub-category picker.
    var isNewTopic: Bool {
        if case .newTopic = target { true } else { false }
    }

    /// The sheet may show the sub-category picker: a new topic, or a first post whose edit form serves the select.
    var offersSubcategories: Bool { isNewTopic || prefill?.subcategories != nil }

    /// The edit of an own message.
    var isEdit: Bool {
        if case .edit = target { true } else { false }
    }

    /// The sheet shows a subject (a new private message, a new topic, a first post's edit) and keeps it in the draft.
    var hasSubjectField: Bool { isNewMessage || isNewTopic || prefill?.subject != nil }

    /// The text holds something to send.
    var hasText: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Send is offered (a new topic waits for its sub-category list, so HFR's default never overrides a choice):
    /// some text (and a subject for a new topic, a recipient and a subject for a new private message), the
    /// draft read, nothing running, not closed. HFR refuses an empty text (`W17a`); a blank recipient or subject is refused here
    /// and by the engine
    /// (HFR's answer to one is not captured).
    var canSend: Bool {
        guard hasText, canEdit, !picker.isLoading else { return false }
        if isNewMessage { return !Self.isBlank(recipient) && !Self.isBlank(subject) }
        // An edit changing nothing would mark the message edited and lose a leading line break HFR does not serve (`R130b`).
        if let prefill, !differsFromPrefill, picker.selected == prefill.subcategories?.preselected { return false }
        return !hasSubjectField || !Self.isBlank(subject)
    }

    /// The fields differ from what the edit form served; always true for the other composers, which start empty.
    var differsFromPrefill: Bool {
        guard let prefill else { return true }
        return text != prefill.text || subject != (prefill.subject ?? "")
    }

    /// Closing asks whether to keep the draft (swiping the sheet down is blocked meanwhile, so it never loses the text). An
    /// edit left as the form served it holds nothing to keep.
    var closeNeedsChoice: Bool { (hasText || !Self.isBlank(subject)) && differsFromPrefill }

    /// What the smiley picker needs: the favourites store, the account key and a fresh search (LOT-105).
    var smileyServices: SmileyPanelServices {
        services.smileyPanel
    }

    /// What the image panel needs (LOT-102).
    var imageUploadServices: ImageUploadServices { services.imageUpload }

    /// One write through the poster, with the fields as they are now. Recipient and subject are trimmed, as legacy Swift did
    /// (`AnswerView.swift:1474`, `MessagesView.swift:4213` @ 21173e77); a line break inside one is refused by the engine.
    func post() async throws(PostingError) -> PostingResult {
        switch target {
        case .reply(let reply):
            return try await services.poster.reply(text, formURL: reply.formURL)
        case .newPrivateMessage(let message):
            return try await services.poster.newPrivateMessage(
                to: recipient.trimmingCharacters(in: .whitespacesAndNewlines),
                subject: subject.trimmingCharacters(in: .whitespacesAndNewlines),
                text: text, formURL: message.formURL
            )
        case .newTopic(let topic):
            return try await services.poster.newTopic(
                subject: subject.trimmingCharacters(in: .whitespacesAndNewlines), subcategory: picker.selected,
                text: text, formURL: topic.formURL
            )
        case .edit(let edit):
            return try await services.poster.edit(
                text, subject: hasSubjectField ? subject.trimmingCharacters(in: .whitespacesAndNewlines) : nil,
                subcategory: picker.selected, target: edit
            )
        }
    }
}
