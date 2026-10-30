import SwiftUI

/// The Messages tab of the iPhone tab bar: the conversation list, then the reader of the chosen conversation. It owns its
/// navigation container (a split view that collapses to a stack on a compact width), so a call site adds none.
struct MessagesRootView: View {
    let model: MessageListModel
    let environment: AppEnvironment
    @State private var column = NavigationSplitViewColumn.sidebar

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $column) {
            MessageListView(model: model)
        } detail: {
            MessageReaderColumn(model: model, reader: environment.reader, composer: environment.composer)
        }
    }
}

/// The Messages list in the content column of the regular-width iPad root, with the conversation in the detail column
/// (`MessageReaderColumn`), the Favoris shape. It owns its navigation stack.
struct MessagesListColumn: View {
    let model: MessageListModel

    var body: some View {
        NavigationStack { MessageListView(model: model) }
    }
}

/// The reader of the conversation chosen in the list.
struct MessageReaderColumn: View {
    let model: MessageListModel
    let reader: ReaderServices
    /// The reply composer (LOT-084); nil when logged out, which hides "Répondre".
    let composer: ComposerServices?

    var body: some View {
        if let thread = model.selected, let readerModel = model.reader(for: thread) {
            TopicReaderView(model: readerModel, services: reader, composer: composer)
                .id(thread.id)
                // Read on HFR only once the page was fetched: a failed or abandoned load leaves the row unread.
                .onChange(of: readerModel.page != nil, initial: true) { _, loaded in
                    if loaded { model.markOpened(thread) }
                }
        } else {
            ContentUnavailableView("Choisissez une conversation", systemImage: "envelope")
        }
    }
}
