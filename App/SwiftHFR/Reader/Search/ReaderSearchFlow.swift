import HFRModels
import SwiftUI

// Port of HFRswift/Swift/MessagesView.swift (the search menu entry, `handleSearchResult`) @ 2440d79. Differences: GAP-130,
// GAP-135: the entry is in the secondary menu and only with an account; a match is followed like a link: scrolled to
// in place when on the page shown (legacy always pushed a `MessagesView`), else a reader above. #821 (operator, 2026-11-16):
// logged out, the entry stays in the menu as in legacy (:5577-5585 @ 87fe0d1c) and a tap asks to sign in (no search request:
// it needs the account's `hash_check`).
/// The reader's search entry (LOT-113): an overflow entry when the page names its topic (a tap asks to sign in without an
/// account, #821), and the search sheet. A match opens in the reader at its message.
struct ReaderSearchFlow: ViewModifier {
    let model: TopicReaderModel
    /// The current account's services; nil when logged out (the search needs the account's `hash_check`).
    let composer: ComposerServices?
    /// Opened by the reader's "…" entry (`ReaderOverflowToolbar`, #645), which owns the item so the menu order is one declaration.
    @Binding var search: TopicSearchModel?
    /// The match found, followed when the sheet has finished closing (a push during the dismissal can be dropped).
    @State private var pendingMatch: ReaderTarget?

    /// What a tap on the entry does.
    enum Tap {
        /// Run the search sheet over the account's searcher.
        case search(topic: TopicID, searcher: any TopicSearching)
        /// Logged out: no request, a prompt to sign in.
        case signIn
    }

    /// Whether the overflow offers the search: a page naming its topic, not a private conversation (not captured), and no open
    /// composer (#653: the "…" overflow stays shut). Without an account it is offered too (#821; the tap asks to sign in), but not
    /// in the offline reader, which has no composer whatever the account (`services.offline` is nil there).
    static func isOffered(model: TopicReaderModel, composer: ComposerServices?, services: ReaderServices) -> Bool {
        isOffered(
            hasTopic: model.page?.topicID != nil, isPrivate: model.isPrivateConversation,
            suspended: model.suspendsPageInteractions, hasSearcher: composer?.topicSearcher != nil,
            isLiveReader: services.offline != nil)
    }

    static func isOffered(hasTopic: Bool, isPrivate: Bool, suspended: Bool, hasSearcher: Bool, isLiveReader: Bool) -> Bool {
        hasTopic && !isPrivate && !suspended && (hasSearcher || isLiveReader)
    }

    /// The outcome of a tap: the searcher exists only with an account, so without one the answer is the sign-in prompt.
    static func tap(topic: TopicID?, searcher: (any TopicSearching)?) -> Tap? {
        guard let topic else { return nil }
        guard let searcher else { return .signIn }
        return .search(topic: topic, searcher: searcher)
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
