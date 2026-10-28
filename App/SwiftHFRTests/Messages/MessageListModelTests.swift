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

func messageThread(_ number: Int, unread: Bool = false, group: Bool = false) -> PrivateMessageThread {
    let summary = TopicSummary(
        topicID: TopicID(category: .privateMessages, topic: number), title: "Sujet \(number)",
        path: "/forum2.php?config=hfr.inc&cat=prive&post=\(number)&page=1&p=1&sondage=0&owntopic=0&trash=0&trash_post=0&print=0"
            + "&numreponse=0&quote_only=0&new=0&nojs=0",
        starterOrInterlocutors: "pseudo\(number)", readState: unread ? .unread : .read
    )
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

    @Test func aThreadShownAsOpenedIsReadUntilTheNextLoad() async throws {
        let source = FakePrivateMessages()
        let model = model(source)
        await model.onAppear()
        let unread = try #require(model.loader.value?.threads.first)
        #expect(model.isUnread(unread))
        #expect(model.unreadCount == 1)
        model.markOpened(unread)
        #expect(!model.isUnread(unread))
        #expect(model.unreadCount == 0)
        await model.refresh()
        #expect(model.isUnread(unread)) // HFR's own state comes back with the next list
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
        model.markOpened(broken)
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
