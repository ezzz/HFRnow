import HFRModels
import Observation

// Port of HFRswift/Swift/MainWindow.swift (ForumTopicsListViewModel) @ 87fe0d1c and HFRswift/Swift/Favorites.swift (FavoritesViewModel)
// @ 2440d79. Differences: the page on screen is kept on refresh, with a retry banner (GAP-025); the Tous / Favoris / Suivis / Lus
// choice applies to a category, not to a sub-forum, whose `subcat` the home links do not give (GAP-023).
/// A group of rows under an optional heading (a favourites category); a forum list has one headless group.
struct TopicGroup: Identifiable, Hashable, Sendable {
    let id: String
    let title: String?
    var topics: [TopicSummary]
    /// Favourites: the header offers to fold the rows (a section without a topic has nothing to fold).
    var isCollapsible = false
    /// Favourites: the header shows, the rows do not.
    var isCollapsed = false
    /// Favourites: the category the heading opens (legacy `headerTitleView`); nil on a forum list and on "Super favoris".
    var opens: TopicSource?
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
    /// Whether the account was signed in when the page was fetched: the filters are the account's lists.
    var isLoggedIn: Bool
    /// The Tous / Favoris / Suivis / Lus filter the page was asked with.
    var filter: TopicListFilter = .all

    var isEmpty: Bool { groups.allSatisfy { $0.topics.isEmpty } }

    init(page: TopicListPage, isLoggedIn: Bool) {
        groups = [TopicGroup(id: "topics", title: nil, topics: page.topics)]
        self.page = page.navigation.current
        hasNext = page.navigation.nextPath != nil
        emptyReason = Self.reason(isEmpty: page.topics.isEmpty, notice: page.notice, isLoggedIn: isLoggedIn)
        newTopicPath = page.newTopicPath
        categoryID = page.categoryID
        self.isLoggedIn = isLoggedIn
    }

    init(favorites: FavoritesPage, isLoggedIn: Bool) {
        groups = favorites.sections.map { TopicGroup(id: $0.id, title: $0.forum.title, topics: $0.topics, opens: $0.source) }
        page = 1
        hasNext = false
        favoritesPage = favorites
        self.isLoggedIn = isLoggedIn
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
    /// The flag writes of the current account (LOT-125); nil when logged out, which hides "Supprimer".
    let flagActions: TopicFlagActions?

    // The row-action state is internal rather than `private(set)` only so `TopicListModel+RowActions.swift` can hold the
    // logic (this type is near its length limit): by convention that file and `load` are the only writers.
    /// Rows marked "Lu" on this device (legacy `isLocallyViewedInApp`), with the `rowActionSerial` of the mark: nothing is
    /// sent, and a load that starts after the mark forgets it.
    var markedRead: [TopicSummary.ID: Int] = [:]
    /// Rows whose flag HFR confirmed removed, with the `rowActionSerial` of the confirmation; a load that starts after it shows
    /// HFR's own state.
    var removedFlags: [TopicSummary.ID: Int] = [:]
    /// Counts the row marks, so a load knows which ones its page already holds (one that left before a mark does not).
    var rowActionSerial = 0
    /// Rows whose flag removal is in flight: offered once, never twice.
    var removingFlags: Set<TopicSummary.ID> = []
    /// Why the last row action did not end as asked, in French; the row stays as it was.
    var actionFailure: String?

    /// The Tous / Favoris / Suivis / Lus choice shared by the lists that offer it; nil where there is none.
    let topicFilter: TopicFilterModel?
    /// The filter the page on screen was asked with.
    var loadedFilter: TopicListFilter { loader.value?.filter ?? .all }
    /// The page on screen was fetched with a signed-in account (false before the first load).
    var isSignedIn: Bool { loader.value?.isLoggedIn ?? false }

    private let dataSource: any ForumDataSource
    private let isLoggedIn: @Sendable () async -> Bool

    /// Creates the model; `isLoggedIn` is read when a load starts. `favorites` applies to the flags and favourites sources only,
    /// `topicFilter` to a category's list.
    init(
        source: TopicSource, dataSource: any ForumDataSource, isLoggedIn: @escaping @Sendable () async -> Bool = { false },
        favorites: FavoritesOptionsModel? = nil, flagActions: TopicFlagActions? = nil, topicFilter: TopicFilterModel? = nil
    ) {
        self.source = source
        self.dataSource = dataSource
        self.isLoggedIn = isLoggedIn
        self.topicFilter = source.supportsFlagFilter ? topicFilter : nil
        self.favorites = source.isFavoritesList ? favorites : nil
        self.flagActions = flagActions
    }

    /// The groups to show: the loaded ones, laid out by the favourites options when there are some. On flags and favourites
    /// a row whose flag was removed leaves the list (legacy `removeTopic`); a forum row stays, without its flag.
    var displayedGroups: [TopicGroup] {
        guard let content = loader.value else { return [] }
        let groups: [TopicGroup]
        if let favorites, let page = content.favoritesPage { groups = favorites.groups(for: page) } else { groups = content.groups }
        guard source.isFavoritesList, !removedFlags.isEmpty else { return groups }
        return groups.map { group in
            var group = group
            group.topics.removeAll { removedFlags[$0.id] != nil }
            if group.topics.isEmpty { group.isCollapsible = false }
            return group
        }
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

    /// Favoris, Suivis and Lus can be chosen: a category list and a signed-in account (legacy disables them logged out,
    /// `MainWindow.swift:683-695` @ 87fe0d1c). "Tous" always can.
    var offersFilter: Bool { topicFilter != nil && source.supportsFlagFilter && isSignedIn }

    /// The filter the list should show now: the stored choice for a signed-in account, "Tous" otherwise.
    var wantedFilter: TopicListFilter { offersFilter ? (topicFilter?.flag.filter ?? .all) : .all }

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
        } else if wantedFilter != loadedFilter {
            // The choice changed here or in another list: HFR's page for it starts at 1 (legacy reloads on every change).
            await load(page: 1)
        } else if !source.isPaged, !loader.isLoading, favorites?.autoRefresh ?? true {
            await refresh()
        }
    }

    /// The top-bar refresh button is enabled unless a load is running (legacy `.disabled(viewModel.isLoading)`,
    /// `MainWindow.swift:381-393` @ 87fe0d1c). Pull-to-refresh is not gated by it: SwiftUI shows its own spinner.
    var canRefresh: Bool { !loader.isLoading }

    /// Reloads the page on screen.
    func refresh() async { await load(page: currentPage) }

    /// Asks again for the last page that was asked for (after a failure).
    func retry() async { await load(page: requestedPage) }

    func goToNextPage() async { if canGoToNext { await load(page: currentPage + 1) } }
    func goToPreviousPage() async { if canGoToPrevious { await load(page: currentPage - 1) } }
    func goToFirstPage() async { if canGoToPrevious { await load(page: 1) } }

    private func load(page: Int) async {
        requestedPage = page
        // Marks made from here on are newer than the page this load brings: they outlive it.
        let startedAfter = rowActionSerial
        let source = source
        let dataSource = dataSource
        let isLoggedIn = isLoggedIn
        // Read here, on the main actor; the signed-in check below runs inside the load, so a second request while one runs
        // never starts a second login read.
        let chosenFilter = topicFilter?.flag.filter ?? .all
        let hasFilter = topicFilter != nil
        let applied = await loader.load { () async throws(ListLoadError) -> TopicListContent in
            let loggedIn = await isLoggedIn()
            let filter = hasFilter && loggedIn ? chosenFilter : .all
            switch source {
            case .subforum(let path, _):
                let list = try await dataSource.topicList(path: path, page: page)
                return TopicListContent(page: list, isLoggedIn: loggedIn)
            case .forum(let category, _):
                let list = try await dataSource.topicList(category: category, filter: filter, page: page)
                var content = TopicListContent(page: list, isLoggedIn: loggedIn)
                content.filter = filter
                return content
            case .flagged:
                return TopicListContent(favorites: try await dataSource.favorites(filter: .flagged), isLoggedIn: loggedIn)
            case .favorites:
                return TopicListContent(favorites: try await dataSource.favorites(filter: .favorites), isLoggedIn: loggedIn)
            }
        }
        // Only the page this call put on screen reconciles: a superseded load (its page dropped) or a failed one changes nothing.
        guard applied else { return }
        // HFR's page now says what is read and flagged: the marks made before this load started are forgotten (legacy kept
        // them in the rows it replaced on reload). A mark made while it was in flight stays: the page may predate it.
        markedRead = markedRead.filter { $0.value > startedAfter }
        removedFlags = removedFlags.filter { $0.value > startedAfter }
        if let page = loader.value?.favoritesPage {
            await favorites?.prune(to: page)
            await favorites?.placePendingSuperFavorites(from: page)
        }
        // The choice changed while this page was loading (or the sign-in turned out different): ask again with the current one.
        if wantedFilter != loadedFilter { await load(page: 1) }
    }
}
