import Foundation
import HFRModels
@testable import SwiftHFR
import Testing

/// A scripted private message source: each call is answered by a closure and recorded.
final class FakePrivateMessages: PrivateMessageSource, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [Int] = []
    var handler: @Sendable (Int) async throws(ListLoadError) -> PrivateMessageListPage = { page in messagePage(page: page) }

    /// Pages asked for, in order.
    var requests: [Int] { lock.withLock { recorded } }

    func privateMessages(page: Int) async throws(ListLoadError) -> PrivateMessageListPage {
        lock.withLock { recorded.append(page) }
        return try await handler(page)
    }
}

/// A login state a test flips between loads.
final class LoginFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = true
    var value: Bool {
        get { lock.withLock { flag } }
        set { lock.withLock { flag = newValue } }
    }
}

/// A row as `R13u1` has them: the title link opens page 1, the latest-message link (`#bas`) names the last page. `pages` 1
/// gives a row with no latest-message link.
func messageThread(_ number: Int, unread: Bool = false, group: Bool = false, pages: Int = 1) -> PrivateMessageThread {
    func link(page: Int) -> String {
        "/forum2.php?config=hfr.inc&cat=prive&post=\(number)&page=\(page)&p=1&sondage=0&owntopic=0&trash=0&trash_post=0&print=0"
            + "&numreponse=0&quote_only=0&new=0&nojs=0"
    }
    var summary = TopicSummary(
        topicID: TopicID(category: .privateMessages, topic: number), title: "Sujet \(number)",
        path: link(page: 1), starterOrInterlocutors: "pseudo\(number)", readState: unread ? .unread : .read
    )
    if pages > 1 {
        summary.pageCount = pages
        summary.lastPagePath = link(page: pages)
        summary.lastPost = LastPost(author: "pseudo\(number)", path: link(page: pages) + "#bas")
    }
    return PrivateMessageThread(summary: summary, interlocutors: ["pseudo\(number)"], isGroup: group)
}

/// A list page `page`, with a next link unless it is page 3: one unread thread, one read group thread.
func messagePage(page: Int) -> PrivateMessageListPage {
    PrivateMessageListPage(
        threads: [messageThread(page * 10, unread: true), messageThread(page * 10 + 1, group: true)],
        navigation: PageNavigation(current: page, last: 3, nextPath: page < 3 ? "/next" : nil, previousPath: page > 1 ? "/prev" : nil)
    )
}

@MainActor
struct MessageListModelTests {
    private func model(_ source: FakePrivateMessages, loggedIn: Bool = true) -> MessageListModel {
        MessageListModel(source: source, isLoggedIn: { loggedIn })
    }

    @Test func firstLoadAsksForPageOneOnce() async {
        let source = FakePrivateMessages()
        let model = model(source)
        await model.onAppear()
        #expect(source.requests == [1])
        #expect(model.currentPage == 1)
        #expect(model.canGoToNext)
        #expect(!model.canGoToPrevious)
    }

    @Test func rowsKeepGroupFlagAndUnreadStateForTheNextLot() async throws {
        let model = model(FakePrivateMessages())
        await model.onAppear()
        let threads = try #require(model.loader.value?.threads)
        #expect(threads.map(\.isUnread) == [true, false])
        #expect(threads.map(\.isGroup) == [false, true])
        #expect(model.loader.value?.unreadCount == 1)
    }

    @Test func loggedOutShowsSignInWithoutAnyRequest() async {
        let source = FakePrivateMessages()
        let model = model(source, loggedIn: false)
        await model.onAppear()
        #expect(source.requests.isEmpty)
        #expect(model.loader.value?.emptyReason == .signInRequired(nil))
        #expect(model.loader.value?.threads.isEmpty == true)
    }

    @Test func emptyMailboxSaysNothing() async {
        let source = FakePrivateMessages()
        source.handler = { _ in PrivateMessageListPage() }
        let model = model(source)
        await model.onAppear()
        #expect(model.loader.value?.emptyReason == .nothing)
    }

    @Test func pagingMovesByOneAndRefreshReloadsThePageOnScreen() async {
        let source = FakePrivateMessages()
        let model = model(source)
        await model.onAppear()
        await model.goToNextPage()
        await model.goToNextPage()
        #expect(!model.canGoToNext)
        await model.refresh()
        await model.goToPreviousPage()
        await model.goToFirstPage()
        #expect(source.requests == [1, 2, 3, 3, 2, 1])
    }

    @Test func appearingAgainRefreshesTheCurrentPage() async {
        let source = FakePrivateMessages()
        let model = model(source)
        await model.onAppear()
        await model.goToNextPage()
        await model.onAppear()
        #expect(source.requests == [1, 2, 2])
    }

    @Test func aFailedRefreshKeepsTheRowsAndRetryAsksForTheSamePage() async {
        let source = FakePrivateMessages()
        let model = model(source)
        await model.onAppear()
        await model.goToNextPage()
        source.handler = { _ async throws(ListLoadError) -> PrivateMessageListPage in throw .timedOut }
        await model.refresh()
        #expect(model.loader.error == .timedOut)
        #expect(model.loader.value?.page == 2)
        source.handler = { page in messagePage(page: page) }
        await model.retry()
        #expect(model.loader.error == nil)
        #expect(source.requests == [1, 2, 2, 2])
    }

    @Test func failureWithoutRowsIsReportedNotHidden() async {
        let source = FakePrivateMessages()
        source.handler = { _ async throws(ListLoadError) -> PrivateMessageListPage in throw .notAuthenticated("Connexion requise") }
        let model = model(source)
        await model.onAppear()
        #expect(model.loader.value == nil)
        #expect(model.loader.error == .notAuthenticated("Connexion requise"))
    }

    /// Parks the calls of a scripted source until the test releases them.
    actor Gate {
        private var isOpen = false
        private var waiters: [CheckedContinuation<Void, Never>] = []

        func wait() async {
            if isOpen { return }
            await withCheckedContinuation { waiters.append($0) }
        }

        func open() {
            isOpen = true
            for waiter in waiters { waiter.resume() }
            waiters = []
        }
    }

    /// Waits (bounded) until the source has been asked `count` times.
    private func waitForRequests(_ source: FakePrivateMessages, _ count: Int) async {
        for _ in 0..<500 where source.requests.count < count { try? await Task.sleep(for: .milliseconds(5)) }
    }

    @Test func aThreadShownAsOpenedIsReadUntilTheNextLoad() async throws {
        let source = FakePrivateMessages()
        let model = model(source)
        await model.onAppear()
        let unread = try #require(model.loader.value?.threads.first)
        #expect(model.isUnread(unread))
        #expect(model.unreadCount == 1)
        model.markOpened(unread, page: 1, of: 1)
        #expect(!model.isUnread(unread))
        #expect(model.unreadCount == 0)
        await model.refresh()
        #expect(model.isUnread(unread)) // HFR's own state comes back with the next list
    }

    @Test func aThreadWithNewerMessagesOnLaterPagesStaysUnreadUntilItsLastPageIsShown() async throws {
        let source = FakePrivateMessages()
        let long = messageThread(40, unread: true, pages: 5)
        source.handler = { _ in PrivateMessageListPage(threads: [long]) }
        let model = model(source)
        await model.onAppear()
        model.markOpened(long, page: 1, of: 5)
        model.markOpened(long, page: 4, of: 5)
        #expect(model.isUnread(long))
        model.markOpened(long, page: 5, of: 5)
        #expect(!model.isUnread(long))
    }

    @Test func aConversationOpensOnThePageOfItsLatestMessage() throws {
        let model = model(FakePrivateMessages())
        let long = messageThread(41, unread: true, pages: 457)
        let reader = try #require(model.reader(for: long))
        #expect(reader.requested.source == .topic(TopicID(category: .privateMessages, topic: 41)))
        #expect(reader.requested.page == 457)
        // No latest-message link on the row: its title link, page 1.
        let plain = try #require(model.reader(for: messageThread(42)))
        #expect(plain.requested.page == 1)
    }

    @Test func aThreadOpenedWhileTheNewestLoadRunsStaysReadWhenItLands() async throws {
        let source = FakePrivateMessages()
        let model = model(source)
        await model.onAppear()
        let unread = try #require(model.loader.value?.threads.first)
        let gate = Gate()
        source.handler = { page async throws(ListLoadError) -> PrivateMessageListPage in
            await gate.wait()
            return messagePage(page: page)
        }
        let refreshing = Task { await model.refresh() }
        await waitForRequests(source, 2)
        model.markOpened(unread, page: 1, of: 1)
        await gate.open()
        await refreshing.value
        #expect(!model.isUnread(unread)) // the answer predates the opening
        await model.refresh()
        #expect(model.isUnread(unread)) // a later load brings HFR's state back
    }

    @Test func aSupersededLoadLandingLateChangesNothing() async throws {
        let source = FakePrivateMessages()
        let model = model(source)
        await model.onAppear()
        let unread = try #require(model.loader.value?.threads.first)
        model.markOpened(unread, page: 1, of: 1)
        let slow = Gate()
        let slower = Gate()
        source.handler = { [source] page async throws(ListLoadError) -> PrivateMessageListPage in
            await (source.requests.count == 2 ? slow : slower).wait()
            return messagePage(page: page)
        }
        let first = Task { await model.refresh() }
        await waitForRequests(source, 2)
        let second = Task { await model.refresh() }
        await waitForRequests(source, 3)
        await slow.open()
        await first.value
        // The newest load is still running: the older one must not have brought HFR's state back.
        #expect(!model.isUnread(unread))
        await slower.open()
        await second.value
        #expect(model.isUnread(unread))
    }

    @Test func aFailedLoadKeepsTheOpenedThreadsRead() async throws {
        let source = FakePrivateMessages()
        let model = model(source)
        await model.onAppear()
        let unread = try #require(model.loader.value?.threads.first)
        model.markOpened(unread, page: 1, of: 1)
        source.handler = { _ async throws(ListLoadError) -> PrivateMessageListPage in throw .timedOut }
        await model.refresh()
        #expect(model.loader.error == .timedOut)
        #expect(!model.isUnread(unread))
    }

    @Test func aRowWithoutAThreadLinkStaysUnread() async throws {
        let source = FakePrivateMessages()
        var changed = messageThread(7, unread: true)
        changed.summary.topicID = nil
        changed.summary.path = "/not-a-thread"
        changed.summary.flagPath = nil
        let broken = changed
        source.handler = { _ in PrivateMessageListPage(threads: [broken]) }
        let model = model(source)
        await model.onAppear()
        model.markOpened(broken, page: 1, of: 1)
        #expect(model.isUnread(broken))
        #expect(model.reader(for: broken) == nil)
    }

    @Test func leavingTheConversationDropsItsReader() {
        let model = model(FakePrivateMessages())
        let thread = messageThread(3)
        model.selected = thread
        let first = model.reader(for: thread)
        model.selected = nil
        #expect(model.reader(for: thread) !== first)
    }

    @Test func aSessionThatExpiresClosesTheOpenConversation() async {
        let session = LoginFlag()
        let model = MessageListModel(source: FakePrivateMessages(), isLoggedIn: { session.value })
        await model.onAppear()
        let thread = messageThread(3)
        model.selected = thread
        #expect(model.reader(for: thread) != nil)
        session.value = false
        await model.refresh()
        #expect(model.loader.value?.emptyReason == .signInRequired(nil))
        #expect(model.selected == nil)
    }

    @Test func aRefusedSessionClosesTheOpenConversationEvenWithItsCookie() async {
        let source = FakePrivateMessages()
        let model = model(source)
        await model.onAppear()
        let thread = messageThread(3)
        model.selected = thread
        source.handler = { _ async throws(ListLoadError) -> PrivateMessageListPage in throw .notAuthenticated("Connexion requise") }
        await model.refresh()
        #expect(model.loader.error == .notAuthenticated("Connexion requise"))
        #expect(model.selected == nil)
        #expect(model.loader.value?.threads.isEmpty == false) // rows kept, as for any failure
    }

    @Test func aFailedRefreshKeepsTheOpenConversation() async {
        let source = FakePrivateMessages()
        let model = model(source)
        await model.onAppear()
        let thread = messageThread(3)
        model.selected = thread
        source.handler = { _ async throws(ListLoadError) -> PrivateMessageListPage in throw .offline }
        await model.refresh()
        #expect(model.selected == thread)
    }

    @Test func aThreadOpensInTheReaderAtItsOwnPage() throws {
        let model = model(FakePrivateMessages())
        let thread = messageThread(3207033)
        let reader = try #require(model.reader(for: thread))
        #expect(reader.requested.source == .topic(TopicID(category: .privateMessages, topic: 3207033)))
        #expect(reader.title == "Sujet 3207033")
        #expect(model.reader(for: thread) === reader)
        #expect(model.reader(for: messageThread(5)) !== reader)
    }
}
