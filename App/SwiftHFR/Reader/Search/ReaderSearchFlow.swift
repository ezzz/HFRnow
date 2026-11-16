import SwiftUI

// Port of HFRswift/Swift/MessagesView.swift (the search menu entry, `handleSearchResult`) @ 2440d79. Differences: GAP-130,
// GAP-135: the entry is in the secondary menu and only with an account; a match is followed like a link: scrolled to
// in place when on the page shown (legacy always pushed a `MessagesView`), else a reader above.
/// The reader's search entry (LOT-113): a toolbar button when an account is current and the page names its topic, and the
/// search sheet. A match opens in the reader at its message.
struct ReaderSearchFlow: ViewModifier {
    let model: TopicReaderModel
    /// The current account's services; nil when logged out (the search needs the account's `hash_check`).
    let composer: ComposerServices?
    /// Opened by the reader's "…" entry (`ReaderOverflowToolbar`, #645), which owns the item so the menu order is one declaration.
    @Binding var search: TopicSearchModel?
    /// The match found, followed when the sheet has finished closing (a push during the dismissal can be dropped).
    @State private var pendingMatch: ReaderTarget?

    /// Whether the overflow offers the search: an account, a page naming its topic, not a private conversation (not captured),
    /// and no open composer (#653: the "…" overflow stays shut).
    static func isOffered(model: TopicReaderModel, composer: ComposerServices?) -> Bool {
        composer?.topicSearcher != nil && model.page?.topicID != nil && !model.isPrivateConversation && !model.suspendsPageInteractions
    }

    func body(content: Content) -> some View {
        content
            .sheet(item: $search, onDismiss: {
                guard let target = pendingMatch else { return }
                pendingMatch = nil
                model.follow(target)
            }, content: { sheet in
                TopicSearchSheet(model: sheet) { target in pendingMatch = target }
            })
    }
}
