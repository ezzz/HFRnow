import HFRModels
import Observation

// Port of the legacy `nb_mp` writes from page loads: `ObjCForumsParser.m:516-525` (home) and `ObjCFavoritesLoaderWorker.m:91-98`
// (favourites and flags), both through `HFRplusAppDelegate.m:704-706` @ 87fe0d1c. Differences: topic lists count too (legacy
// parses their header, `ObjCTopicListParser.m:83-92`, but its Swift layer never applies it); no local decrement when a
// conversation is opened (`MPListView.swift:497-502`) and no background check (LOT-140) (GAP-004).
/// The unread private messages count of the Messages badge: the newest one HFR announced on a list page this session loaded.
///
/// Every load takes a ticket when it starts; its count applies only when no load that started later has applied one, so a
/// slow answer never puts back an older count. A page without the private messages entry (nil) says nothing and keeps it.
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
}

/// A data source that hands the count of every page it loads to `count`: the home page, topic lists, favourites and flags.
struct PrivateMessageCountingSource: ForumDataSource {
    let base: any ForumDataSource
    let count: PrivateMessageCount

    func forumList() async throws(ListLoadError) -> ForumListPage {
        try await counted(\.unreadPrivateMessages) { () async throws(ListLoadError) in try await base.forumList() }
    }

    func topicList(category: CategoryID, filter: TopicListFilter, page: Int) async throws(ListLoadError) -> TopicListPage {
        try await counted(\.unreadPrivateMessages) { () async throws(ListLoadError) in
            try await base.topicList(category: category, filter: filter, page: page)
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
