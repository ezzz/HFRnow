import HFRModels
import Observation

/// A group of rows under an optional heading (a favourites category); a forum list has one headless group.
struct TopicGroup: Identifiable, Hashable, Sendable {
    let id: String
    let title: String?
    let topics: [TopicSummary]
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

    var isEmpty: Bool { groups.allSatisfy { $0.topics.isEmpty } }

    init(page: TopicListPage, isLoggedIn: Bool) {
        groups = [TopicGroup(id: "topics", title: nil, topics: page.topics)]
        self.page = page.navigation.current
        hasNext = page.navigation.nextPath != nil
        emptyReason = Self.reason(isEmpty: page.topics.isEmpty, notice: page.notice, isLoggedIn: isLoggedIn)
    }

    init(favorites: FavoritesPage, isLoggedIn: Bool) {
        groups = favorites.sections.map { TopicGroup(id: $0.id, title: $0.forum.title, topics: $0.topics) }
        page = 1
        hasNext = false
        emptyReason = Self.reason(isEmpty: favorites.sections.allSatisfy { $0.topics.isEmpty }, notice: favorites.notice, isLoggedIn: isLoggedIn)
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

    private let dataSource: any ForumDataSource
    private let isLoggedIn: @Sendable () async -> Bool

    /// Creates the model; `isLoggedIn` is read when a load starts.
    init(source: TopicSource, dataSource: any ForumDataSource, isLoggedIn: @escaping @Sendable () async -> Bool = { false }) {
        self.source = source
        self.dataSource = dataSource
        self.isLoggedIn = isLoggedIn
    }

    /// Page on screen; 1 before the first load.
    var currentPage: Int { loader.value?.page ?? 1 }
    var canGoToPrevious: Bool { source.isPaged && currentPage > 1 && !loader.isLoading }
    var canGoToNext: Bool { source.isPaged && (loader.value?.hasNext ?? false) && !loader.isLoading }

    /// Loads page 1 once; later calls keep what is shown.
    func loadIfNeeded() async {
        guard loader.value == nil, !loader.isLoading else { return }
        await load(page: 1)
    }

    /// The list became visible: first load, or a refresh for flags and favourites, whose content changes while the user
    /// reads elsewhere. Rows stay meanwhile. Forum pages are left alone: the user refreshes those.
    func onAppear() async {
        if loader.value == nil { await loadIfNeeded() } else if !source.isPaged, !loader.isLoading { await refresh() }
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
    }
}
