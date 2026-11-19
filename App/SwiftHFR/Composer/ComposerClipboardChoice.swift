import Foundation

/// One button of the clipboard question (#1180): a verb that names what it does, and a real « Annuler ». Legacy's alert answered
/// « Non » / « Oui », and its cancel-role button still inserted the tag, so Esc inserted it too (`AnswerView.swift:530-557` @ 87fe0d1c).
struct ClipboardChoice: Equatable, Identifiable {
    enum Kind: Equatable {
        /// Use the clipboard: wrap or insert it (the question's first answer).
        case accept
        /// « [url=XXX] » form of the empty-selection link.
        case acceptAttribute
        /// Insert the plain tags, the clipboard left alone.
        case withoutClipboard
        /// Back out of the tap: nothing is inserted.
        case cancel
    }

    let kind: Kind
    let title: String
    var id: Kind { kind }
}

extension ComposerFormattingModel.Pending {
    /// The buttons of the question, in the order shown; « Annuler » is always the last and the only cancel.
    var choices: [ClipboardChoice] {
        let without = ClipboardChoice(kind: .withoutClipboard, title: "Insérer sans le presse-papiers")
        let cancel = ClipboardChoice(kind: .cancel, title: "Annuler")
        switch self {
        case .link:
            return [ClipboardChoice(kind: .accept, title: "Coller le lien"), without, cancel]
        case .linkChoice:
            return [
                ClipboardChoice(kind: .acceptAttribute, title: "Insérer [url=XXX]"),
                ClipboardChoice(kind: .accept, title: "Insérer [url]XXX[/url]"),
                without,
                cancel
            ]
        case .formatting:
            return [ClipboardChoice(kind: .accept, title: "Insérer"), without, cancel]
        }
    }
}

extension ComposerFormattingModel {
    /// Applies a button of the question; `current` is the question it was shown for (the dialog clears `pending` before the action).
    func choose(_ choice: ClipboardChoice, for current: Pending) {
        switch choice.kind {
        case .accept: acceptPending(current)
        case .acceptAttribute: acceptLinkChoice(current, attribute: true)
        case .withoutClipboard: declinePending(current)
        case .cancel: dismissPending()
        }
    }
}
