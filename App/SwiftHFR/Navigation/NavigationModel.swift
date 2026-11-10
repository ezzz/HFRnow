import HFRModels
import HFRStorage
import Observation

/// Selection and per-screen models of the three-column navigation: forums, topics, messages.
@MainActor
@Observable
final class NavigationModel {
    let forums: ForumListModel
    /// Forum, flags or favourites chosen in the sidebar.
    var selectedSource: TopicSource? {
        didSet {
            guard selectedSource != oldValue else { return }
            // Another source starts from a fresh reader: a cached one could still hold a followed link's reader (CodeRabbit, #389).
            selectedTopic = nil
            currentReader = nil
            requestedOpening = nil
            // Picking the flags or the favourites is the favourites mode (`vos_sujets`), so it is what the tab opens on next time.
            if let mode = selectedSource?.favoritesMode { favorites?.mode = mode }
        }
    }
    /// Options of the favourites lists (LOT-124); nil on the Catégories tab.
    let favorites: FavoritesOptionsModel?
    /// The Tous / Favoris / Suivis / Lus choice of the category lists; nil where the tab has none (Favoris).
    let topicFilter: TopicFilterModel?
    /// Favoris: the category a section title pushed on the favourites list (legacy pushed `ForumTopicsListView` in the Favoris
    /// stack); the selection stays on the favourites.
    var openedCategory: TopicSource?
    /// Topic chosen in the middle column, shown by the reader in the detail column.
    var selectedTopic: TopicSummary?
    /// Changes each time a row's menu opens a page (LOT-125), so the detail column builds a new reader for it even when the
    /// topic was already selected.
    private(set) var readerGeneration = 0
    /// The post filter (LOT-114), started from a favourite or the reader menu; one per navigation, so a run survives a
    /// change of column.
    let filtering: FilteredPostsModel

    private let dataSource: any ForumDataSource
    /// The flag writes the lists offer (LOT-125); nil when logged out.
    let flagActions: TopicFlagActions?
    private let topicPages: any TopicPageSource
    private let renderOptions: @Sendable () -> ReaderRenderOptions
    /// The reader of the selected topic, created once per selection so a view update never refetches the page (E25).
    @ObservationIgnored private var currentReader: (id: String, model: TopicReaderModel)?
    /// The page a row's menu asked for, used by the next reader of that topic instead of the row's own link.
    @ObservationIgnored private var requestedOpening: (id: String, opening: TopicOpening)?
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
        filteredPosts: FilteredPostsServices = .unavailable,
        startupSource: TopicSource? = nil,
        favorites: FavoritesOptionsModel? = nil,
        flagActions: TopicFlagActions? = nil,
        topicFilter: TopicFilterModel? = nil
    ) {
        self.favorites = favorites
        self.topicFilter = topicFilter
        self.flagActions = flagActions
        filtering = FilteredPostsModel(services: filteredPosts)
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
        let model = TopicListModel(
            source: source, dataSource: dataSource, isLoggedIn: { [weak self] in await self?.isLoggedIn() ?? false },
            favorites: favorites, flagActions: flagActions, topicFilter: topicFilter
        )
        topicLists[source] = model
        return model
    }

    /// Opens `category` from a Favoris heading with the filter of the favourites `mode` (legacy `initialFlagOverride`, which also
    /// wrote the global choice: so does this).
    func openCategory(_ category: TopicSource, mode: FavoritesSource) {
        topicFilter?.flag = mode.categoryFlag
        openedCategory = category
    }

    /// The sub-forum menu and filter of the forum list `source`; nil for flags and favourites, or where the tab has no filter.
    func scope(for source: TopicSource) -> ForumScope? {
        guard let topicFilter, source.isForumList else { return nil }
        return ForumScope(
            section: { [forums] in forums.loader.value?.section(containing: source) }, filter: topicFilter,
            select: { [weak self] in
                // In Favoris the category was pushed, so a sub-forum replaces it there; in Catégories it is the selection.
                if self?.favorites != nil { self?.openedCategory = $0 } else { self?.selectedSource = $0 }
            }
        )
    }

    /// The reader of `topic`: the same model while the topic stays selected, a new one (a new load) for another topic.
    /// Nil when the row names no topic page.
    func reader(for topic: TopicSummary) -> TopicReaderModel? {
        if let currentReader, currentReader.id == topic.id { return currentReader.model }
        let opening = requestedOpening?.id == topic.id ? requestedOpening?.opening : ReaderTarget(opening: topic).map {
            TopicOpening(target: $0)
        }
        requestedOpening = nil
        guard let opening else { return nil }
        let model = TopicReaderModel(
            target: opening.target, title: topic.title, source: topicPages, opensAtLastMessage: opening.atLastMessage,
            renderOptions: renderOptions
        )
        currentReader = (topic.id, model)
        return model
    }

    /// Opens `topic` at `opening` (a row menu's "Première page", "Dernière page"…, LOT-125): a new reader, even for the topic
    /// on screen.
    func open(_ topic: TopicSummary, at opening: TopicOpening) {
        requestedOpening = (topic.id, opening)
        currentReader = nil
        readerGeneration += 1
        selectedTopic = topic
    }
}

/// A topic page source that has no forum behind it (previews and tests that never open a topic).
struct UnavailableTopicPages: TopicPageSource {
    func page(for target: ReaderTarget) async throws(ListLoadError) -> ReaderPage { throw .other }
}
