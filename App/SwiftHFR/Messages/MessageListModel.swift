import HFRModels
import Observation

/// A private message list page ready to display.
struct MessageListContent: Sendable, Equatable {
    /// Conversations in page order. Each row keeps its own unread state and group flag, so a later lot can split or count
    /// them without fetching again (LOT-171).
    var threads: [PrivateMessageThread]
    /// Page shown (1-based).
    var page: Int
    /// A next page exists. The pager is a window, so only "there is a next page" is known, never a total.
    var hasNext: Bool
    /// Why there is no row, when there is none.
    var emptyReason: EmptyReason?

    /// Conversations of this page the member has not read; the mailbox total is the badge's (home page), not this.
    var unreadCount: Int { threads.filter(\.isUnread).count }

    init(threads: [PrivateMessageThread], page: Int, hasNext: Bool, emptyReason: EmptyReason?) {
        self.threads = threads
        self.page = page
        self.hasNext = hasNext
        self.emptyReason = emptyReason
    }

    init(page list: PrivateMessageListPage) {
        threads = list.threads
        page = list.navigation.current
        hasNext = list.navigation.nextPath != nil
        emptyReason = list.threads.isEmpty ? .nothing : nil
    }

    /// What a logged-out visitor sees: no request is made, the list asks for a login.
    static let signedOut = MessageListContent(threads: [], page: 1, hasNext: false, emptyReason: .signInRequired(nil))
}

/// State of the private message list (LOT-126): one page at a time, the conversation opened in the reader.
///
/// Same loading rules as the topic lists (one load at a time, rows kept while reloading or after a failure, refresh reloads
/// the page on screen). Logged out, nothing is requested: the list says a login is needed.
@MainActor
@Observable
final class MessageListModel {
    let loader = ContentLoader<MessageListContent>()
    /// Conversation chosen in the list, shown by the reader.
    var selected: PrivateMessageThread?

    /// Page of the last load that was asked for; a retry after a failure goes back to it.
    private(set) var requestedPage = 1

    private let source: any PrivateMessageSource
    private let isLoggedIn: @Sendable () async -> Bool
    private let topicPages: any TopicPageSource
    private let renderOptions: @Sendable () -> ReaderRenderOptions
    /// The reader of the selected conversation, created once per selection so a view update never refetches the page (E25).
    /// Threads opened since the last load; a load brings HFR's own state back.
    private var openedThreads: Set<String> = []
    @ObservationIgnored private var currentReader: (id: String, model: TopicReaderModel)?

    /// Creates the model; `isLoggedIn` is read when a load starts.
    init(
        source: any PrivateMessageSource,
        isLoggedIn: @escaping @Sendable () async -> Bool = { false },
        topicPages: any TopicPageSource = UnavailableTopicPages(),
        renderOptions: @escaping @Sendable () -> ReaderRenderOptions = { ReaderRenderOptions() }
    ) {
        self.source = source
        self.isLoggedIn = isLoggedIn
        self.topicPages = topicPages
        self.renderOptions = renderOptions
    }

    /// Page on screen; 1 before the first load.
    var currentPage: Int { loader.value?.page ?? 1 }
    var canGoToPrevious: Bool { currentPage > 1 && !loader.isLoading }
    var canGoToNext: Bool { (loader.value?.hasNext ?? false) && !loader.isLoading }

    /// The list became visible: first load, or a refresh, because reading a conversation elsewhere changes its unread state.
    /// Rows stay meanwhile.
    func onAppear() async {
        guard !loader.isLoading else { return }
        await load(page: loader.value == nil ? 1 : currentPage)
    }

    /// Reloads the page on screen.
    func refresh() async { await load(page: currentPage) }

    /// Asks again for the last page that was asked for (after a failure).
    func retry() async { await load(page: requestedPage) }

    func goToNextPage() async { if canGoToNext { await load(page: currentPage + 1) } }
    func goToPreviousPage() async { if canGoToPrevious { await load(page: currentPage - 1) } }
    func goToFirstPage() async { if canGoToPrevious { await load(page: 1) } }

    /// The reader of `thread`: the same model while it stays selected, a new one (a new load) for another conversation.
    /// Nil when the row names no thread page.
    func reader(for thread: PrivateMessageThread) -> TopicReaderModel? {
        if let currentReader, currentReader.id == thread.id { return currentReader.model }
        guard let target = ReaderTarget(opening: thread.summary) else { return nil }
        let model = TopicReaderModel(target: target, title: thread.summary.title, source: topicPages, renderOptions: renderOptions)
        currentReader = (thread.id, model)
        return model
    }

    /// Whether the row shows as unread: HFR's state, until the member opens it (the reader's fetch is what marks it read).
    func isUnread(_ thread: PrivateMessageThread) -> Bool {
        thread.isUnread && !openedThreads.contains(thread.id)
    }

    /// Conversations of this page still unread for the member.
    var unreadCount: Int { loader.value?.threads.filter { isUnread($0) }.count ?? 0 }

    /// Remembers that the member opened `thread`, so its row is shown read at once, without a request.
    /// A row that names no thread page opens nothing, so it stays unread.
    func markOpened(_ thread: PrivateMessageThread) {
        guard ReaderTarget(opening: thread.summary) != nil else { return }
        openedThreads.insert(thread.id)
    }

    private func load(page: Int) async {
        requestedPage = page
        let source = source
        let isLoggedIn = isLoggedIn
        await loader.load { () async throws(ListLoadError) -> MessageListContent in
            guard await isLoggedIn() else { return .signedOut }
            return MessageListContent(page: try await source.privateMessages(page: page))
        }
        if loader.error == nil { openedThreads = [] }
    }
}
