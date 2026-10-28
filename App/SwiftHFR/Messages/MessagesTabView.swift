import SwiftUI

/// The single entry point of the Messages screen: the conversation list, then the reader of the chosen conversation.
/// The root navigation (LOT-170) shows it as the Messages tab; on a compact width the split view collapses to a stack.
struct MessagesTabView: View {
    @State private var model: MessageListModel
    private let reader: ReaderServices
    @State private var column = NavigationSplitViewColumn.sidebar

    init(environment: AppEnvironment) {
        reader = environment.reader
        _model = State(initialValue: environment.makeMessageList())
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $column) {
            MessageListView(model: model)
        } detail: {
            if let thread = model.selected, let readerModel = model.reader(for: thread) {
                TopicReaderView(model: readerModel, services: reader)
                    .id(thread.id)
            } else {
                ContentUnavailableView("Choisissez une conversation", systemImage: "envelope")
            }
        }
    }
}
