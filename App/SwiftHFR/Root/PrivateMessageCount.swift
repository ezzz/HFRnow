import HFRModels
import Observation

// Port of the legacy `nb_mp` writes (all @ 87fe0d1c, through `HFRplusAppDelegate.m:704-706`): from the home page
// (`ObjCForumsParser.m:516-525`), the favourites and flags (`ObjCFavoritesLoaderWorker.m:91-98`), and the local -1 / +1 when an
// unread conversation is opened or one is marked unread (`MPListView.swift:497-502`, `:536-540`). Differences (GAP-004, #762):
// - topic lists count too: legacy's Swift layer parses their header (`ObjCTopicListParser.m:83-92`) without applying it, only
//   the ObjC `TopicsTableViewController.m:426-427` does;
// - topic pages are not counted: legacy reads the 3-cell header of every topic page (`MessagesTableViewController.m:931-944`,
//   `OnlineMessagesTableViewController.m:442-453`),
//   which logged-in public topics carry (R21, R63a) and the captured MP thread pages do not (R123b, RA1, RU2: 2 cells), and
//   `TopicPage` does not expose it;
// - the -1 comes when the conversation's last page is shown (the row's own read rule), not on the tap;
// - a logged-out home page sets 0, so an expired session clears the badge without a root rebuild; no background check (LOT-140).
/// The unread private messages count of the Messages badge: the newest one HFR announced on a list page this session loaded,
/// moved by one when a conversation is read or marked unread here.
///
/// Every load takes a ticket when it starts; its count applies only when no load that started later has applied one, so a
/// slow answer never puts back an older count. A page without the private messages entry (nil) says nothing and keeps it.
/// A local change takes a ticket too, so a load already in flight, whose page predates it, cannot undo it (LESSONS 57).
@MainActor
@Observable
final class PrivateMessageCount {
    /// HFR's latest count; nil before any page carried one (logged out, or nothing loaded yet).
    private(set) var latest: Int?
    @ObservationIgnored private var issued = 0
    @ObservationIgnored private var applied = 0

    /// A ticket for a load that starts now.
    func ticket() -> Int {
        issued += 1
        return issued
    }

    /// Records what the page of the load holding `ticket` announced.
    func record(_ count: Int?, ticket: Int) {
        guard let count, ticket > applied else { return }
        applied = ticket
        latest = count
    }

    /// Moves the count by `delta` after a change made here (a conversation read or marked unread), never below 0; nothing
    /// before a page gave a count.
    func adjust(by delta: Int) {
        guard let latest else { return }
        self.latest = max(latest + delta, 0)
        applied = ticket()
    }
}

/// A data source that hands the count of every page it loads to `count`: the home page, topic lists, favourites and flags.
struct PrivateMessageCountingSource: ForumDataSource {
    let base: any ForumDataSource
    let count: PrivateMessageCount

    /// A logged-out home page has no private messages entry: 0, so a session that expired in place clears the badge.
    func forumList() async throws(ListLoadError) -> ForumListPage {
        try await counted(\.loggedInUnreadPrivateMessages) { () async throws(ListLoadError) in try await base.forumList() }
    }

    func topicList(
        category: CategoryID, subcategory: Int?, filter: TopicListFilter, page: Int
    ) async throws(ListLoadError) -> TopicListPage {
        try await counted(\.unreadPrivateMessages) { () async throws(ListLoadError) in
            try await base.topicList(category: category, subcategory: subcategory, filter: filter, page: page)
        }
    }

    func topicList(path: String, page: Int) async throws(ListLoadError) -> TopicListPage {
        try await counted(\.unreadPrivateMessages) { () async throws(ListLoadError) in try await base.topicList(path: path, page: page) }
    }

    func favorites(filter: TopicListFilter) async throws(ListLoadError) -> FavoritesPage {
        try await counted(\.unreadPrivateMessages) { () async throws(ListLoadError) in try await base.favorites(filter: filter) }
    }

    private func counted<Page>(
        _ unread: KeyPath<Page, Int?>, _ load: () async throws(ListLoadError) -> Page
    ) async throws(ListLoadError) -> Page {
        let ticket = await count.ticket()
        let page = try await load()
        let announced = page[keyPath: unread]
        await count.record(announced, ticket: ticket)
        return page
    }
}

private extension ForumListPage {
    /// The count a home page gives the badge: its own, or 0 when it is a logged-out page.
    var loggedInUnreadPrivateMessages: Int? { isLoggedIn ? unreadPrivateMessages : 0 }
}
