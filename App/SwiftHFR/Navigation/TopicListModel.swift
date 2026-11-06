import HFRModels
import Observation

// Port of HFRswift/Swift/MainWindow.swift (ForumTopicsListViewModel) and HFRswift/Swift/Favorites.swift (FavoritesViewModel) @ 2440d79.
// Differences: the page on screen is kept on refresh, with a retry banner (GAP-025).
/// A group of rows under an optional heading (a favourites category); a forum list has one headless group.
struct TopicGroup: Identifiable, Hashable, Sendable {
    let id: String
    let title: String?
    let topics: [TopicSummary]
    /// Favourites: the header offers to fold the rows (a section without a topic has nothing to fold).
    var isCollapsible = false
    /// Favourites: the header shows, the rows do not.
    var isCollapsed = false
}

/// Why a list has no row, so the screen says what to do instead of showing a blank page.
enum EmptyReason: Hashable, Sendable {
    /// The list is legitimately empty.
    case nothing
    /// HFR answered with a message instead of a list; logged out, that is the login wall.
    case signInRequired(String?)
    /// HFR answered with a message instead of a list, for a logged-in account.
    case notice(String)
}

/// A topic list page ready to display.
struct TopicListContent: Sendable, Equatable {
    var groups: [TopicGroup]
    /// Page shown (1-based); always 1 for flags and favourites.
    var page: Int
    /// A next page exists. Honest paging: the pager is a window, so only "there is a next page" is known, never a total.
    var hasNext: Bool
    var emptyReason: EmptyReason?
    /// The page's "new topic" link (`md_btn_new_topic`, LOT-089) and the category it belongs to; nil on flags and favourites.
    var newTopicPath: String?
    var categoryID: CategoryID?
    /// The favourites page the groups come from, kept so the layout options apply without a new request; nil for a forum list.
    var favoritesPage: FavoritesPage?

    var isEmpty: Bool { groups.allSatisfy { $0.topics.isEmpty } }

    init(page: TopicListPage, isLoggedIn: Bool) {
        groups = [TopicGroup(id: "topics", title: nil, topics: page.topics)]
        self.page = page.navigation.current
        hasNext = page.navigation.nextPath != nil
        emptyReason = Self.reason(isEmpty: page.topics.isEmpty, notice: page.notice, isLoggedIn: isLoggedIn)
        newTopicPath = page.newTopicPath
        categoryID = page.categoryID
    }

    init(favorites: FavoritesPage, isLoggedIn: Bool) {
        groups = favorites.sections.map { TopicGroup(id: $0.id, title: $0.forum.title, topics: $0.topics) }
        page = 1
        hasNext = false
        favoritesPage = favorites
        let isEmpty = favorites.sections.allSatisfy { $0.topics.isEmpty }
        emptyReason = Self.reason(isEmpty: isEmpty, notice: favorites.notice, isLoggedIn: isLoggedIn)
    }

    private static func reason(isEmpty: Bool, notice: String?, isLoggedIn: Bool) -> EmptyReason? {
        guard isEmpty else { return nil }
        guard let notice else { return .nothing }
        return isLoggedIn ? .notice(notice) : .signInRequired(notice)
    }
}

/// State of one topic list (forum, flags or favourites).
///
/// Refresh reloads the page on screen, not page 1, keeps the rows meanwhile and after a failure (LOTS "Issues to open" #6).
@MainActor
@Observable
final class TopicListModel {
    let source: TopicSource
    let loader = ContentLoader<TopicListContent>()

    /// Page of the last load that was asked for; a retry after a failure goes back to it.
    private(set) var requestedPage = 1
    /// HFR's confirmation of the topic just created (LOT-089), shown above the list until hidden.
    private(set) var sentConfirmation: String?

    /// Layout options, collapsed sections and super-favourites of the favourites lists (LOT-124); nil for forum lists.
    let favorites: FavoritesOptionsModel?

    private let dataSource: any ForumDataSource
    private let isLoggedIn: @Sendable () async -> Bool

    /// Creates the model; `isLoggedIn` is read when a load starts. `favorites` applies to the flags and favourites sources only.
    init(
        source: TopicSource, dataSource: any ForumDataSource, isLoggedIn: @escaping @Sendable () async -> Bool = { false },
        favorites: FavoritesOptionsModel? = nil
    ) {
        self.source = source
        self.dataSource = dataSource
        self.isLoggedIn = isLoggedIn
        self.favorites = source.isFavoritesList ? favorites : nil
    }

    /// The groups to show: the loaded ones, laid out by the favourites options when there are some.
    var displayedGroups: [TopicGroup] {
        guard let content = loader.value else { return [] }
        guard let favorites, let page = content.favoritesPage else { return content.groups }
        return favorites.groups(for: page)
    }

    /// The page has topics but the options hide every section: the screen says so instead of looking empty.
    var allSectionsHidden: Bool {
        guard let content = loader.value, content.favoritesPage != nil, !content.isEmpty else { return false }
        return displayedGroups.isEmpty
    }

    /// Whether `topic` is a super-favourite (tinted row).
    func isSuperFavorite(_ topic: TopicSummary) -> Bool {
        guard let favorites else { return false }
        return FavoritesPresentation.isSuper(topic, in: favorites.superFavorites)
    }

    /// Page on screen; 1 before the first load.
    var currentPage: Int { loader.value?.page ?? 1 }
    var canGoToPrevious: Bool { source.isPaged && currentPage > 1 && !loader.isLoading }
    var canGoToNext: Bool { source.isPaged && (loader.value?.hasNext ?? false) && !loader.isLoading }

    /// The new-topic composer the page on screen links to (legacy "+" button, `MainWindow.swift:748-757` @ 2440d79, enabled
    /// when `newTopicURL`, GAP-098, read from `md_btn_new_topic`, exists); nil before a load, on flags and favourites, in the private
    /// messages category, or without that link (logged out pages carry it too: the screen offers it to a current account only).
    var newTopicTarget: NewTopicTarget? {
        guard let content = loader.value else { return nil }
        return NewTopicTarget(path: content.newTopicPath, forum: content.categoryID)
    }

    /// The new-topic sheet closed. After HFR's confirmation (it refreshes to the category list and names no topic, `W40`, so
    /// the new topic is not opened) page 1 is reloaded, where it appears. After an
    /// unconfirmed send page 1 is reloaded too, so the user sees whether it went. Closing with or without the draft changes
    /// nothing.
    func newTopicDidClose(_ reason: ReplyComposerModel.CloseReason) async {
        switch reason {
        case .sent(let result):
            sentConfirmation = result.message
            await load(page: 1)
        case .checkTopic:
            await load(page: 1)
        case .keptDraft, .discardedDraft, .closedWithoutSaving:
            break
        }
    }

    /// Hides the confirmation of the topic just created.
    func clearSentConfirmation() {
        sentConfirmation = nil
    }

    /// Loads page 1 once; later calls keep what is shown.
    func loadIfNeeded() async {
        guard loader.value == nil, !loader.isLoading else { return }
        await load(page: 1)
    }

    /// The list became visible: first load, or a refresh for flags and favourites, whose content changes while the user
    /// reads elsewhere. Rows stay meanwhile. Forum pages are left alone: the user refreshes those.
    ///
    /// Favourites refresh on their own only with "Actualisation automatique" (`favorites_auto_refresh`, legacy default off):
    /// otherwise the list is refreshed by pull or by the refresh action.
    func onAppear() async {
        await favorites?.reload()
        if loader.value == nil {
            await loadIfNeeded()
        } else if !source.isPaged, !loader.isLoading, favorites?.autoRefresh ?? true {
            await refresh()
        }
    }

    /// Reloads the page on screen.
    func refresh() async { await load(page: currentPage) }

    /// Asks again for the last page that was asked for (after a failure).
    func retry() async { await load(page: requestedPage) }

    func goToNextPage() async { if canGoToNext { await load(page: currentPage + 1) } }
    func goToPreviousPage() async { if canGoToPrevious { await load(page: currentPage - 1) } }
    func goToFirstPage() async { if canGoToPrevious { await load(page: 1) } }

    private func load(page: Int) async {
        requestedPage = page
        let source = source
        let dataSource = dataSource
        let isLoggedIn = isLoggedIn
        await loader.load { () async throws(ListLoadError) -> TopicListContent in
            let loggedIn = await isLoggedIn()
            switch source {
            case .subforum(let path, _):
                let list = try await dataSource.topicList(path: path, page: page)
                return TopicListContent(page: list, isLoggedIn: loggedIn)
            case .forum(let category, _):
                let list = try await dataSource.topicList(category: category, page: page)
                return TopicListContent(page: list, isLoggedIn: loggedIn)
            case .flagged:
                return TopicListContent(favorites: try await dataSource.favorites(filter: .flagged), isLoggedIn: loggedIn)
            case .favorites:
                return TopicListContent(favorites: try await dataSource.favorites(filter: .favorites), isLoggedIn: loggedIn)
            }
        }
        if loader.error == nil, let page = loader.value?.favoritesPage { await favorites?.prune(to: page) }
    }
}
