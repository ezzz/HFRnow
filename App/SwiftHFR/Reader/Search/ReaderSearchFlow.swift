import SwiftUI

/// The reader's search entry (LOT-113): a toolbar button when an account is current and the page names its topic, and the
/// search sheet. A match opens in the reader at its message.
struct ReaderSearchFlow: ViewModifier {
    let model: TopicReaderModel
    /// The current account's services; nil when logged out (the search needs the account's `hash_check`).
    let composer: ComposerServices?
    @State private var search: TopicSearchModel?

    func body(content: Content) -> some View {
        content
            .toolbar {
                if let searcher = composer?.topicSearcher, let topic = model.page?.topicID {
                    ToolbarItem(placement: .primaryAction) {
                        Button { search = TopicSearchModel(topic: topic, searcher: searcher) } label: {
                            Label("Rechercher dans le sujet", systemImage: "magnifyingglass")
                        }
                    }
                }
            }
            .sheet(item: $search) { sheet in
                TopicSearchSheet(model: sheet) { target in Task { await model.open(target) } }
            }
    }
}
