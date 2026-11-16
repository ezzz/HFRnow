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
    }

    // Legacy lists page 1 of `cat=prive` and nothing else (`ObjCMPTopicsLoaderWorker.m:9-15` @ 87fe0d1c): a list whose page
    // says "a next page exists" still fetches page 1 only, on load, refresh, retry and reappearing, and the content carries
    // no page number or next-page flag, so nothing can drive a pager (it and "Page N" are gone, #968).
    @Test func theListFetchesPageOneOnlyAndExposesNoPagingState() async {
        let source = FakePrivateMessages()
        let model = model(source)
        await model.onAppear()
        #expect(model.loader.value?.threads.count == 2)
        await model.refresh()
        await model.onAppear()
        source.handler = { _ async throws(ListLoadError) -> PrivateMessageListPage in throw .timedOut }
        await model.refresh()
        source.handler = { page in messagePage(page: page) }
        await model.retry()
        #expect(source.requests == [1, 1, 1, 1, 1])
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

    @Test func aFailedRefreshKeepsTheRowsAndRetryAsksAgain() async {
        let source = FakePrivateMessages()
        let model = model(source)
        await model.onAppear()
        source.handler = { _ async throws(ListLoadError) -> PrivateMessageListPage in throw .timedOut }
        await model.refresh()
        #expect(model.loader.error == .timedOut)
        #expect(model.loader.value?.threads.count == 2)
        source.handler = { page in messagePage(page: page) }
        await model.retry()
        #expect(model.loader.error == nil)
        #expect(source.requests == [1, 1, 1])
    }

    @Test func failureWithoutRowsIsReportedNotHidden() async {
        let source = FakePrivateMessages()
        source.handler = { _ async throws(ListLoadError) -> PrivateMessageListPage in throw .notAuthenticated("Connexion requise") }
        let model = model(source)
        await model.onAppear()
        #expect(model.loader.value == nil)
        #expect(model.loader.error == .notAuthenticated("Connexion requise"))
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
        #expect(reader.requested.page == 1) // a one-page thread: its title link
        #expect(model.reader(for: thread) === reader)
        #expect(model.reader(for: messageThread(5)) !== reader)
    }
}
