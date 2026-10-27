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
    private var topicLists: [TopicSource: TopicListModel] = [:]

    /// Creates the navigation over `dataSource`.
    init(dataSource: any ForumDataSource, forums: ForumListModel? = nil) {
        self.dataSource = dataSource
        self.forums = forums ?? ForumListModel(dataSource: dataSource)
    }

    /// Whether the account is signed in, as the last forum list says.
    var isLoggedIn: Bool { forums.loader.value?.isLoggedIn ?? false }

    /// The model of `source`, created once so going back keeps rows, page and scroll position.
    func topicList(for source: TopicSource) -> TopicListModel {
        if let existing = topicLists[source] { return existing }
        let model = TopicListModel(source: source, dataSource: dataSource, isLoggedIn: { [weak self] in self?.isLoggedIn ?? false })
        topicLists[source] = model
        return model
    }
}
