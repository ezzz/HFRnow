import HFRModels
import HFRNetwork
import Observation

// DO NOT MERGE (#1276): a trace name that never carries a forum path or title.
extension TopicSource {
    var traceName: String {
        switch self {
        case .favorites: "favorites"
        case .flagged: "flagged"
        case .forum: "forum"
        case .subforum: "subforum"
        }
    }
}

// Port of HFRswift/Swift/MainWindow.swift (ForumTopicsListViewModel) @ 87fe0d1c and HFRswift/Swift/Favorites.swift (FavoritesViewModel)
// @ 2440d79. Differences: the page on screen is kept on refresh, with a retry banner (GAP-025); a sub-forum's `subcat` comes from
// its own page's "new topic" link, as the home links do not give it (GAP-023), so its filter starts after the first page.
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
    /// A next page exists. The pager is a window: the count `pageCount` is a lower bound unless `pageCountIsExact`.
    var hasNext: Bool
    /// HFR's last page (`navigation.last`, a lower bound when HFR's pager is a window), at least `page`: « page x / y » (#980).
    var pageCount: Int = 1
    /// `PageNavigation.isExact`; « page x / y+ » when false. Also true on the last page, where the pager has nothing to hide.
    var pageCountIsExact: Bool = true
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
        pageCount = max(page.navigation.last, page.navigation.current + (hasNext ? 1 : 0))
        pageCountIsExact = page.navigation.isExact || !hasNext
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
    private(set) var sentConfirmation: String? {
        didSet { confirmationDidChange() }
    }

    /// Clears a success confirmation by itself after `ConfirmationAutoDismiss.delay` (#864).
    let confirmationTimer = ConfirmationAutoDismiss()

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
    /// The row whose removal failed with nothing sent and may work if sent again: the failure offers « Réessayer » (#1056).
    var retryableRemoval: TopicSummary?

    /// The Tous / Favoris / Suivis / Lus choice shared by the lists that offer it; nil where there is none.
    let topicFilter: TopicFilterModel?
    /// The filter the page on screen was asked with.
    var loadedFilter: TopicListFilter { loader.value?.filter ?? .all }
    /// The category and `subcat` a sub-forum's own page named (`SubforumTarget`); nil on other sources and until it is known.
    private(set) var subforumTarget: SubforumTarget?
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
        // « Non lus » with nothing unread left (#1058): no row, so no empty header either, whatever the empty-sections setting says.
        if showsNoUnreadFavorites { return [] }
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

    /// A row of the favourites page shows unread pages and still has its flag (#1058): « Non lus » can have something to show.
    var hasUnreadFavoriteRows: Bool {
        guard let page = loader.value?.favoritesPage else { return false }
        return page.sections.contains { $0.topics.contains { FavoritesPresentation.isUnread($0) && removedFlags[$0.id] == nil } }
    }

    /// « Non lus » is on, the page has favourites and none is unread (#1058): the screen says so instead of listing nothing or
    /// empty headers. An unread row inside a folded section counts as unread, so this is false then.
    var showsNoUnreadFavorites: Bool {
        guard favorites?.unreadOnly == true, let content = loader.value else { return false }
        guard content.favoritesPage != nil, !content.isEmpty else { return false }
        return !hasUnreadFavoriteRows
    }

    /// Whether `topic` is a super-favourite (tinted row).
    func isSuperFavorite(_ topic: TopicSummary) -> Bool {
        guard let favorites else { return false }
        return FavoritesPresentation.isSuper(topic, in: favorites.superFavorites)
    }

    /// Favoris, Suivis and Lus can be chosen: a category list (or a sub-forum whose `subcat` is known) and a signed-in account
    /// (legacy disables them logged out, `MainWindow.swift:683-695` @ 87fe0d1c). "Tous" always can.
    var offersFilter: Bool {
        guard topicFilter != nil, source.supportsFlagFilter, isSignedIn else { return false }
        if case .subforum = source { return subforumTarget != nil }
        return true
    }

    /// The filter the list should show now: the stored choice for a signed-in account, "Tous" otherwise.
    var wantedFilter: TopicListFilter { offersFilter ? (topicFilter?.flag.filter ?? .all) : .all }

    /// Page on screen; 1 before the first load.
    var currentPage: Int { loader.value?.page ?? 1 }
    var canGoToPrevious: Bool { source.isPaged && currentPage > 1 && !loader.isLoading }
    /// Pages in the list and whether that is the real last page; 1 and true before the first load.
    var pageCount: Int { loader.value?.pageCount ?? 1 }
    var pageCountIsExact: Bool { loader.value?.pageCountIsExact ?? true }
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

    /// A shown confirmation is a success HFR confirmed: it goes by itself; the cross is the other way (#864).
    private func confirmationDidChange() {
        guard sentConfirmation != nil else { return confirmationTimer.cancel() }
        confirmationTimer.arm { [weak self] in self?.clearSentConfirmation() }
    }

    /// In-place changes of the session so far, and the one the page on screen was loaded under (#1195).
    @ObservationIgnored private var sessionChanges = 0
    @ObservationIgnored private var pageSessionChanges = 0

    /// The session changed in place (#1195): the page on screen says nothing reliable about the sign-in any more; it is
    /// reloaded from page 1 when the list is shown again (`onAppear`) or now (`reloadAfterSessionChange`).
    func sessionDidChange() {
        sessionChanges += 1
    }

    /// Reloads page 1 when the page on screen predates a change of the session: the filter it may offer changed with the
    /// sign-in, and HFR's page for a filter starts at 1.
    func reloadAfterSessionChange() async {
        guard loader.value != nil || loader.isLoading, pageSessionChanges != sessionChanges else { return }
        await load(page: 1)
    }

    /// Loads page 1 once; later calls keep what is shown.
    func loadIfNeeded() async {
        T1276.log("list \(source.traceName) loadIfNeeded value=\(loader.value != nil) loading=\(loader.isLoading)")
        guard loader.value == nil, !loader.isLoading else { return }
        await load(page: 1)
    }

    /// The list became visible: first load, or a refresh for flags and favourites, whose content changes while the user
    /// reads elsewhere. Rows stay meanwhile. Forum pages are left alone: the user refreshes those.
    ///
    /// Favourites refresh on their own only with "Actualisation automatique" (`favorites_auto_refresh`, legacy default off):
    /// otherwise the list is refreshed by pull or by the refresh action.
    func onAppear() async {
        T1276.log(
            "list \(source.traceName) onAppear start fav=\(favorites != nil) value=\(loader.value != nil) "
                + "loading=\(loader.isLoading)"
        )
        await favorites?.reload()
        T1276.log("list \(source.traceName) onAppear after favorites.reload")
        if loader.value == nil {
            await loadIfNeeded()
        } else if pageSessionChanges != sessionChanges {
            // Loaded before a re-login or an expiry in place: signed-in state, filter and notices are those of then (#1195).
            await load(page: 1)
        } else if wantedFilter != loadedFilter {
            // The choice changed here or in another list: HFR's page for it starts at 1 (legacy reloads on every change).
            await load(page: 1)
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
    /// Offered only when `pageCount` is the real last page.
    var canGoToLast: Bool { canGoToNext && (loader.value?.pageCountIsExact ?? false) }
    func goToLastPage() async { if canGoToLast { await load(page: pageCount) } }
    /// Exactly HFR page `page`; clamped to 1...`pageCount` unless that is only a lower bound.
    func goToPage(_ page: Int) async {
        guard source.isPaged, !loader.isLoading else { return }
        let target = pageCountIsExact ? min(max(page, 1), pageCount) : max(page, 1)
        if target != currentPage { await load(page: target) }
    }

    /// What the pager's page menu asks for (#980); the same rules as the MP list's (#968).
    func perform(_ jump: PagerJump) async {
        switch jump {
        case .first: await goToFirstPage()
        case .previous: await goToPreviousPage()
        case .next: await goToNextPage()
        case .last: await goToLastPage()
        case .page(let page): await goToPage(page)
        }
    }

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
        let target = subforumTarget
        let startedUnder = sessionChanges
        let traceName = source.traceName
        T1276.log("list \(traceName) load page=\(page)")
        let applied = await loader.load { () async throws(ListLoadError) -> TopicListContent in
            T1276.log("list \(traceName) isLoggedIn ask")
            let loggedIn = await isLoggedIn()
            T1276.log("list \(traceName) isLoggedIn=\(loggedIn)")
            let filter = hasFilter && loggedIn ? chosenFilter : .all
            switch source {
            case .subforum(let path, _):
                // Filtered through the category list with the sub-forum's `subcat` (`R603d`); without the id yet, or on "Tous",
                // the sub-forum's own page, which names it.
                guard filter != .all, let target else {
                    let list = try await dataSource.topicList(path: path, page: page)
                    return TopicListContent(page: list, isLoggedIn: loggedIn)
                }
                let list = try await dataSource.topicList(
                    category: target.category, subcategory: target.subcategory, filter: filter, page: page
                )
                var content = TopicListContent(page: list, isLoggedIn: loggedIn)
                content.filter = filter
                return content
            case .forum(let category, _):
                let list = try await dataSource.topicList(category: category, subcategory: nil, filter: filter, page: page)
                var content = TopicListContent(page: list, isLoggedIn: loggedIn)
                content.filter = filter
                return content
            case .flagged:
                return TopicListContent(favorites: try await dataSource.favorites(filter: .flagged), isLoggedIn: loggedIn)
            case .favorites:
                return TopicListContent(favorites: try await dataSource.favorites(filter: .favorites), isLoggedIn: loggedIn)
            }
        }
        T1276.log("list \(traceName) load page=\(page) applied=\(applied) error=\(loader.error?.traceName ?? "-")")
        // Only the page this call put on screen reconciles: a superseded load (its page dropped) or a failed one changes nothing.
        guard applied else { return }
        pageSessionChanges = startedUnder
        if case .subforum = source, let found = SubforumTarget(newTopicPath: loader.value?.newTopicPath) { subforumTarget = found }
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
