import HFRModels
import Observation

/// Selection and per-screen models of the three-column navigation: forums, topics, messages.
@MainActor
@Observable
final class NavigationModel {
    let forums: ForumListModel
    /// Forum, flags or favourites chosen in the sidebar.
    var selectedSource: TopicSource? {
        didSet { if selectedSource != oldValue { selectedTopic = nil } }
    }
    /// Topic chosen in the middle column, shown by the reader in the detail column.
    var selectedTopic: TopicSummary?

    private let dataSource: any ForumDataSource
    private let topicPages: any TopicPageSource
    private let renderOptions: @Sendable () -> ReaderRenderOptions
    /// The reader of the selected topic, created once per selection so a view update never refetches the page (E25).
    @ObservationIgnored private var currentReader: (id: String, model: TopicReaderModel)?
    private let sessionIsLoggedIn: @Sendable () async -> Bool
    /// A cache, not display state: `topicList(for:)` is called from a view body and must not invalidate it.
    @ObservationIgnored private var topicLists: [TopicSource: TopicListModel] = [:]

    /// Creates the navigation over `dataSource`.
    init(
        dataSource: any ForumDataSource,
        forums: ForumListModel? = nil,
        sessionIsLoggedIn: @escaping @Sendable () async -> Bool = { false },
        topicPages: any TopicPageSource = UnavailableTopicPages(),
        renderOptions: @escaping @Sendable () -> ReaderRenderOptions = { ReaderRenderOptions() },
        startupSource: TopicSource? = nil
    ) {
        self.dataSource = dataSource
        self.topicPages = topicPages
        self.renderOptions = renderOptions
        self.sessionIsLoggedIn = sessionIsLoggedIn
        self.forums = forums ?? ForumListModel(dataSource: dataSource)
        // `didSet` does not run in `init`; no topic is chosen yet anyway.
        selectedSource = startupSource
    }

    /// Whether the account is signed in: what the last forum list says, else what the session says (a list opened before the
    /// home page loaded must not call a plain HFR notice a login wall).
    func isLoggedIn() async -> Bool {
        if let known = forums.loader.value?.isLoggedIn { return known }
        return await sessionIsLoggedIn()
    }

    /// The model of `source`, created once so going back keeps rows, page and scroll position.
    func topicList(for source: TopicSource) -> TopicListModel {
        if let existing = topicLists[source] { return existing }
        let model = TopicListModel(source: source, dataSource: dataSource, isLoggedIn: { [weak self] in await self?.isLoggedIn() ?? false })
        topicLists[source] = model
        return model
    }

    /// The reader of `topic`: the same model while the topic stays selected, a new one (a new load) for another topic.
    /// Nil when the row names no topic page.
    func reader(for topic: TopicSummary) -> TopicReaderModel? {
        if let currentReader, currentReader.id == topic.id { return currentReader.model }
        guard let target = ReaderTarget(opening: topic) else { return nil }
        let model = TopicReaderModel(target: target, title: topic.title, source: topicPages, renderOptions: renderOptions)
        currentReader = (topic.id, model)
        return model
    }
}

/// A topic page source that has no forum behind it (previews and tests that never open a topic).
struct UnavailableTopicPages: TopicPageSource {
    func page(for target: ReaderTarget) async throws(ListLoadError) -> ReaderPage { throw .other }
}
