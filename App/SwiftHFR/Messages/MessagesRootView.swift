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
            MessageReaderColumn(model: model, reader: environment.reader, composer: nil)
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
    /// Callers pass nil until LOT-128: an MP reply is a state-changing flow of its own (RA1-RA5 carry a `cat=prive` answer link,
    /// but the refresh after posting on such a thread is not captured), so no "Répondre" on a conversation yet.
    let composer: ComposerServices?

    var body: some View {
        if let thread = model.selected, let readerModel = model.reader(for: thread) {
            TopicReaderView(model: readerModel, services: reader, composer: composer)
                .id(thread.id)
                // Shown read only once the conversation's last page was fetched: a failed or abandoned load, or an earlier page
                // with newer messages unseen, leaves the row unread.
                .onChange(of: readerModel.page.map { $0.currentPage >= $0.maxPage } ?? false, initial: true) { _, onLastPage in
                    if onLastPage, let page = readerModel.page { model.markOpened(thread, page: page.currentPage, of: page.maxPage) }
                }
        } else {
            ContentUnavailableView("Choisissez une conversation", systemImage: "envelope")
        }
    }
}
