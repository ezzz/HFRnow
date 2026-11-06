import Foundation
import HFRModels
@testable import SwiftHFR
import Testing

/// `MessageListModel`'s read state: which rows show as read, when a load brings back HFR's own state, and where a
/// conversation opens.
// The suite limit is a backstop for a hang only: on a loaded simulator it measures the shared main-actor queue (#366).
@MainActor @Suite(.timeLimit(.minutes(5)))
struct MessageListReadStateTests {
    private func model(_ source: FakePrivateMessages, loggedIn: Bool = true) -> MessageListModel {
        MessageListModel(source: source, isLoggedIn: { loggedIn })
    }

    @Test func aThreadShownAsOpenedIsReadUntilTheNextLoad() async throws {
        let source = FakePrivateMessages()
        let model = model(source)
        await model.onAppear()
        let unread = try #require(model.loader.value?.threads.first)
        #expect(model.isUnread(unread))
        model.markOpened(unread, page: 1, of: 1)
        #expect(!model.isUnread(unread))
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

    @Test func aConversationOpensOnThePageOfItsLatestMessage() async throws {
        let model = MessageListModel(source: FakePrivateMessages(), isLoggedIn: { true }, topicPages: FakeTopicPages())
        let long = messageThread(41, unread: true, pages: 457)
        let reader = try #require(model.reader(for: long))
        #expect(reader.requested.source == .topic(TopicID(category: .privateMessages, topic: 41)))
        #expect(reader.requested.page == 457)
        // Legacy opens the latest-message link (`#bas`): the reader scrolls to the page's last message (45701 of readerPage).
        await reader.onAppear()
        #expect(reader.document?.anchor == 45_701)
        // No latest-message link on the row: its title link, page 1, from the top.
        let plain = try #require(model.reader(for: messageThread(42)))
        #expect(plain.requested.page == 1)
        await plain.onAppear()
        #expect(plain.document?.anchor == nil)
    }

    @Test func aThreadOpenedWhileTheNewestLoadRunsStaysReadWhenItLands() async throws {
        let source = FakePrivateMessages()
        let model = model(source)
        await model.onAppear()
        let unread = try #require(model.loader.value?.threads.first)
        let gate = CheckGate()
        source.handler = { page async throws(ListLoadError) -> PrivateMessageListPage in
            await gate.wait()
            return messagePage(page: page)
        }
        let refreshing = gate.run { await model.refresh() }
        guard await gate.entered() else { Issue.record("The refresh never asked for its page"); return }
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
        let slow = CheckGate()
        let slower = CheckGate()
        source.handler = { [source] page async throws(ListLoadError) -> PrivateMessageListPage in
            await (source.requests.count == 2 ? slow : slower).wait()
            return messagePage(page: page)
        }
        let first = slow.run { await model.refresh() }
        guard await slow.entered() else { Issue.record("The first refresh never asked for its page"); return }
        let second = slower.run { await model.refresh() }
        guard await slower.entered() else {
            Issue.record("The second refresh never asked for its page")
            await slow.open()
            return
        }
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

    @Test func anOpenedThreadStaysReadAfterAFailedRefreshAndTheNextGoodLoadBringsBackHFRsState() async throws {
        let source = FakePrivateMessages()
        let model = model(source)
        await model.onAppear()
        let unread = try #require(model.loader.value?.threads.first)
        model.markOpened(unread, page: 1, of: 1)
        source.handler = { _ async throws(ListLoadError) -> PrivateMessageListPage in throw .offline }
        await model.refresh()
        await model.refresh()
        #expect(!model.isUnread(unread)) // two failures: nothing was brought back
        source.handler = { page in messagePage(page: page) }
        await model.retry()
        #expect(model.loader.error == nil)
        #expect(model.isUnread(unread))
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
}
