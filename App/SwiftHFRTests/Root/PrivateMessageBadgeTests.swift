import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// The Messages badge follows the newest count HFR announced on a list page, moved by one when a conversation is read or
/// marked unread here (#762): legacy rewrites `nb_mp` from every home and favourites page it parses (`ObjCForumsParser.m:516-525`,
/// `ObjCFavoritesLoaderWorker.m:91-98` @ 87fe0d1c) and moves it locally (`MPListView.swift:497-502`, `:536-540`).
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
        // A load in flight when a conversation was read here brings a page from before the read: it must not undo it.
        let inFlight = count.ticket()
        count.adjust(by: -1)
        count.record(5, ticket: inFlight)
        #expect(count.latest == 4)
    }

    // Reverting `PrivateMessageCountingSource.forumList` to the page's own count (nil logged out) fails this test: a session
    // that expired in place (same generation, no root rebuild) kept the old badge, where the home-page badge fell to 0.
    @Test func aLoggedOutHomePageClearsTheCount() async {
        let source = FakeDataSource()
        let state = HomeState()
        source.forumHandler = { state.page }
        let root = root(source)
        await root.forums.loadIfNeeded()
        #expect(root.unreadPrivateMessages == 7)
        state.page = ForumListPage(forums: [], isLoggedIn: false, unreadPrivateMessages: nil)
        await root.forums.reload()
        #expect(root.unreadPrivateMessages == 0)
    }

    // #762's scenario: the launch said 7 and the member reads an unread conversation here; no list page loads, and legacy
    // shows 6 at once. Removing the `adjust(by: -1)` of `markOpened` fails this test.
    @Test func readingAnUnreadConversationToItsLastPageTakesOneOffOnce() async {
        let count = PrivateMessageCount()
        count.record(7, ticket: count.ticket())
        let thread = messageThread(7, unread: true, pages: 2)
        let model = messages(with: thread, count: count)
        await model.onAppear()
        model.markOpened(thread, page: 1, of: 2)
        #expect(count.latest == 7)
        model.markOpened(thread, page: 2, of: 2)
        #expect(count.latest == 6)
        model.markOpened(thread, page: 2, of: 2)
        #expect(count.latest == 6)
        // A conversation already read takes nothing off.
        let read = messageThread(8)
        model.markOpened(read, page: 1, of: 1)
        #expect(count.latest == 6)
    }

    // Removing the `adjust(by: 1)` of `markUnreadEnded` fails this test; a row already unread adds nothing.
    @Test func markingAReadConversationUnreadAddsOne() async {
        let count = PrivateMessageCount()
        count.record(6, ticket: count.ticket())
        let read = messageThread(8)
        let source = FakePrivateMessages()
        source.handler = { _ in PrivateMessageListPage(threads: [read]) }
        let model = MessageListModel(source: source, isLoggedIn: { true }, topicPages: FakeTopicPages(), privateMessageCount: count)
        await model.onAppear()
        // The reload after the write fails, so the row stays marked unread: a second confirmation finds it unread.
        source.handler = { _ async throws(ListLoadError) -> PrivateMessageListPage in throw .offline }
        let reader = TopicReaderModel(
            target: ReaderTarget(source: .topic(TopicID(category: .privateMessages, topic: 8))), title: "", source: FakeTopicPages()
        )
        await model.markUnreadEnded(read, in: reader, .done("Le message a été marqué comme non lu avec succès"))
        #expect(count.latest == 7)
        await model.markUnreadEnded(read, in: reader, .done("Le message a été marqué comme non lu avec succès"))
        #expect(count.latest == 7)
    }

    // Round 2: the reader keeps the thread value of the tap. Open (7 → 6), the list reloads with the row read, then the reader
    // shows the last page again with that stale value: HFR says 6, so nothing more comes off. Deciding from the argument
    // instead of the row the list holds fails this test (5).
    @Test func aStaleThreadValueAfterAReloadTakesNothingMoreOff() async {
        let count = PrivateMessageCount()
        count.record(7, ticket: count.ticket())
        let tapped = messageThread(7, unread: true, pages: 2)
        let source = FakePrivateMessages()
        source.handler = { _ in PrivateMessageListPage(threads: [tapped]) }
        let model = MessageListModel(source: source, isLoggedIn: { true }, topicPages: FakeTopicPages(), privateMessageCount: count)
        await model.onAppear()
        model.markOpened(tapped, page: 2, of: 2)
        #expect(count.latest == 6)
        source.handler = { _ in PrivateMessageListPage(threads: [messageThread(7, pages: 2)]) }
        await model.refresh()
        model.markOpened(tapped, page: 2, of: 2)
        #expect(count.latest == 6)
    }

    // The same stale value on "Marquer comme non lu": the list now holds the row read, so HFR's confirmation adds one.
    // Deciding from the argument (unread) fails this test (6).
    @Test func aStaleThreadValueAfterAReloadStillAddsOneOnMarkUnread() async {
        let count = PrivateMessageCount()
        count.record(7, ticket: count.ticket())
        let tapped = messageThread(7, unread: true, pages: 2)
        let source = FakePrivateMessages()
        source.handler = { _ in PrivateMessageListPage(threads: [tapped]) }
        let model = MessageListModel(source: source, isLoggedIn: { true }, topicPages: FakeTopicPages(), privateMessageCount: count)
        await model.onAppear()
        model.markOpened(tapped, page: 2, of: 2)
        source.handler = { _ in PrivateMessageListPage(threads: [messageThread(7, pages: 2)]) }
        await model.refresh()
        #expect(count.latest == 6)
        source.handler = { _ async throws(ListLoadError) -> PrivateMessageListPage in throw .offline }
        let reader = TopicReaderModel(
            target: ReaderTarget(source: .topic(TopicID(category: .privateMessages, topic: 7))), title: "", source: FakeTopicPages()
        )
        await model.markUnreadEnded(tapped, in: reader, .done("Le message a été marqué comme non lu avec succès"))
        #expect(count.latest == 7)
    }

    private func messages(with thread: PrivateMessageThread, count: PrivateMessageCount) -> MessageListModel {
        let source = FakePrivateMessages()
        source.handler = { _ in PrivateMessageListPage(threads: [thread]) }
        return MessageListModel(source: source, isLoggedIn: { true }, topicPages: FakeTopicPages(), privateMessageCount: count)
    }
}

/// The home page a scripted source answers, changed between loads.
private final class HomeState: @unchecked Sendable {
    private let lock = NSLock()
    private var current = ForumListPage(forums: [], isLoggedIn: true, unreadPrivateMessages: 7)
    var page: ForumListPage {
        get { lock.withLock { current } }
        set { lock.withLock { current = newValue } }
    }
}
