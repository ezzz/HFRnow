import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// The Messages badge follows the newest count HFR announced on a list page (#762): legacy rewrites `nb_mp` from every
/// home and favourites page it parses (`ObjCForumsParser.m:516-525`, `ObjCFavoritesLoaderWorker.m:91-98` @ 87fe0d1c).
@MainActor
struct PrivateMessageBadgeTests {
    private func root(_ source: FakeDataSource) -> RootModel {
        let count = PrivateMessageCount()
        let counted = PrivateMessageCountingSource(base: source, count: count)
        let forums = ForumListModel(dataSource: counted)
        return RootModel(
            forums: forums,
            categories: NavigationModel(dataSource: counted, forums: forums, startupSource: RootModel.categoriesStartupSource),
            favorites: NavigationModel(dataSource: counted, forums: forums, startupSource: RootModel.favoritesStartupSource),
            messages: MessageListModel(source: FakePrivateMessages()),
            store: InMemorySettingsStore(), privateMessageCount: count
        )
    }

    // #762: the home page loaded at launch said 7, a conversation was read since, and the favourites page now says 6. Reading
    // the badge from the launch's home page alone keeps 7 and fails this test.
    @Test func aLaterFavouritesPageReplacesTheCountOfTheHomePage() async {
        let source = FakeDataSource()
        source.forumHandler = { ForumListPage(forums: [], isLoggedIn: true, unreadPrivateMessages: 7) }
        source.favoritesHandler = { _ in FavoritesPage(unreadPrivateMessages: 6) }
        let root = root(source)
        await root.forums.loadIfNeeded()
        #expect(root.unreadPrivateMessages == 7)
        await root.favorites.topicList(for: .favorites).loadIfNeeded()
        #expect(root.unreadPrivateMessages == 6)
    }

    // A forum list's header carries the count too (`PrivateMessageBadgeParser.countInListHeader`, P03f); the MP list and a
    // page without the entry give nil, which says nothing and keeps the count.
    @Test func aTopicListHeaderUpdatesTheCountAndAPageWithoutTheEntryKeepsIt() async {
        let source = FakeDataSource()
        source.forumHandler = { ForumListPage(forums: [], isLoggedIn: true, unreadPrivateMessages: 7) }
        source.topicHandler = { _, page in
            var list = topicPage(page: page)
            list.unreadPrivateMessages = page == 1 ? 0 : nil
            return list
        }
        let root = root(source)
        await root.forums.loadIfNeeded()
        let list = root.categories.topicList(for: .forum(.forum(13), title: "Discussions"))
        await list.loadIfNeeded()
        #expect(root.unreadPrivateMessages == 0)
        await list.goToNextPage()
        #expect(source.requests.last == "topics:13:2")
        #expect(root.unreadPrivateMessages == 0)
    }

    // Removing the ticket check of `PrivateMessageCount.record` fails this test: a load that started first and answers last
    // would put back an older count.
    @Test func aLoadThatStartedEarlierNeverOverwritesANewerCount() {
        let count = PrivateMessageCount()
        let older = count.ticket()
        let newer = count.ticket()
        count.record(6, ticket: newer)
        count.record(7, ticket: older)
        #expect(count.latest == 6)
        // A newer load that failed records nothing: an older one answering after it is then the newest count known.
        let earlier = count.ticket()
        _ = count.ticket()
        count.record(5, ticket: earlier)
        #expect(count.latest == 5)
    }
}
