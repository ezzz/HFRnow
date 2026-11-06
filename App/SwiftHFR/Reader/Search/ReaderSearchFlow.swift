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
    @State private var search: TopicSearchModel?
    /// The match found, followed when the sheet has finished closing (a push during the dismissal can be dropped).
    @State private var pendingMatch: ReaderTarget?

    func body(content: Content) -> some View {
        content
            .toolbar {
                // Searching a private conversation (`cat=prive`) is not captured: no entry there.
                if let searcher = composer?.topicSearcher, let topic = model.page?.topicID, !model.isPrivateConversation {
                    ToolbarItem(placement: .secondaryAction) {
                        Button { search = TopicSearchModel(topic: topic, searcher: searcher) } label: {
                            Label("Rechercher dans le sujet", systemImage: "magnifyingglass")
                        }
                    }
                }
            }
            .sheet(item: $search, onDismiss: {
                guard let target = pendingMatch else { return }
                pendingMatch = nil
                model.follow(target)
            }, content: { sheet in
                TopicSearchSheet(model: sheet) { target in pendingMatch = target }
            })
    }
}
