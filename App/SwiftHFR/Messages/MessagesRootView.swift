import SwiftUI

// Port of HFRswift/Swift/MainWindow.swift (RootTabView, Messages tab) and HFRswift/Swift/MPListView.swift (MPListView) @ 2440d79.
// Differences: a split view on a regular width (GAP-212, UXD), except an iPhone of compact height, a stack as legacy (#431);
// the account button is top left, as `MainToolbar.swift:60-66` @ 87fe0d1c (#1057).
/// The Messages tab of the iPhone tab bar: the conversation list, then the reader of the chosen conversation. It owns its
/// navigation container (a split view that collapses to a stack on a compact width), so a call site adds none.
struct MessagesRootView: View {
    let model: MessageListModel
    let reader: ReaderServices
    /// The current account's composer; nil when logged out.
    let composer: ComposerServices?
    @State private var column = NavigationSplitViewColumn.sidebar

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $column) {
            MessageListView(model: model, composer: composer).accountMenuToolbarItem().appScreenBackground()
        } detail: {
            MessageReaderColumn(model: model, reader: reader, composer: composer).appScreenBackground()
        }
        // A landscape Pro Max reads full width, as legacy's stack (#431).
        .modifier(TabSplitWidth())
        // A conversation selected by the model (the thread of a new MP) is shown on a compact width too, as a tap would; one it
        // closed (marked unread, LOT-127) goes back to the list, as legacy pops.
        .onChange(of: model.selected) { _, selected in
            column = selected == nil ? .sidebar : .detail
        }
    }
}

/// The Messages list in the content column of the regular-width iPad root, with the conversation in the detail column
/// (`MessageReaderColumn`), the Favoris shape. It owns its navigation stack.
struct MessagesListColumn: View {
    let model: MessageListModel
    /// The current account's composer (new private message); nil when logged out.
    let composer: ComposerServices?

    var body: some View {
        ThemedNavigationStack { MessageListView(model: model, composer: composer) }
    }
}

/// The reader of the conversation chosen in the list.
struct MessageReaderColumn: View {
    let model: MessageListModel
    let reader: ReaderServices
    /// The current account's composer: "Répondre" on a conversation (LOT-128) through its `cat=prive` answer link (`RA1`-`RA4`,
    /// reply form `R47b`, answer `W11`); nil when logged out.
    let composer: ComposerServices?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        if let thread = model.selected, let readerModel = model.reader(for: thread) {
            // Its own stack, for the readers a followed link pushes (LOT-137); a new conversation starts a new stack.
            ThemedNavigationStack {
                TopicReaderView(
                    model: readerModel, services: reader, composer: composer,
                    onMarkUnread: { [model] outcome in await model.markUnreadEnded(thread, in: readerModel, outcome) }
                )
            }
                .id("\(thread.id)#\(model.readerGeneration)")
                // Shown read only once the conversation's last page was fetched: a failed or abandoned load, or an earlier page
                // with newer messages unseen, leaves the row unread.
                .onChange(of: readerModel.page.map { $0.currentPage >= $0.maxPage } ?? false, initial: true) { _, onLastPage in
                    if onLastPage, let page = readerModel.page { model.markOpened(thread, page: page.currentPage, of: page.maxPage) }
                }
                // EXPERIMENTAL(mpDarkTopic, #858): each page shown moves the group's position (legacy's flag, after every load).
                .onChange(of: MPReachedMessage(reader: readerModel, of: thread), initial: true) { _, reached in
                    if let reached { model.noteReached(reached, in: thread) }
                }
                // EXPERIMENTAL(mpDarkTopic, #858): a row that stays selected (iPad) sends its flags when the reader leaves the
                // screen or the app the foreground, not only when another conversation is chosen.
                .onDisappear { model.flushMovedFlags() }
                .onChange(of: scenePhase) { _, phase in
                    if phase != .active { model.flushMovedFlags() }
                }
        } else {
            ContentUnavailableView("Choisissez une conversation", systemImage: "envelope")
        }
    }
}
