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
    /// Topic chosen in the middle column (the message pane is a placeholder until the topic reader lands).
    var selectedTopic: TopicSummary?

    private let dataSource: any ForumDataSource
    private let sessionIsLoggedIn: @Sendable () async -> Bool
    /// A cache, not display state: `topicList(for:)` is called from a view body and must not invalidate it.
    @ObservationIgnored private var topicLists: [TopicSource: TopicListModel] = [:]

    /// Creates the navigation over `dataSource`.
    init(
        dataSource: any ForumDataSource,
        forums: ForumListModel? = nil,
        sessionIsLoggedIn: @escaping @Sendable () async -> Bool = { false }
    ) {
        self.dataSource = dataSource
        self.sessionIsLoggedIn = sessionIsLoggedIn
        self.forums = forums ?? ForumListModel(dataSource: dataSource)
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
}
