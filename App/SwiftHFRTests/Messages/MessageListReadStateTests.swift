import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

// The suite limit is a backstop for a hang only: on a loaded simulator it measures the shared main-actor queue (#366).
/// `MessageListModel`'s read state: which rows show as read, when a load brings back HFR's own state, and where a
/// conversation opens.
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

    /// A list counting one unread conversation on HFR's badge and recording what it hands to the notification ledger.
    private func counted(_ source: FakePrivateMessages, badge: Int, recorder: SeenRecorder) -> (MessageListModel, PrivateMessageCount) {
        let count = PrivateMessageCount()
        count.record(badge, ticket: count.ticket())
        let model = MessageListModel(
            source: source, isLoggedIn: { true }, privateMessageCount: count, ledgerSeen: { recorder.add($0) },
            ledgerThread: { recorder.add(thread: $0, mark: $1) }
        )
        return (model, count)
    }

    /// Runs `action` while the list's reload is stopped under it with no newer load of the list: the load applies nothing.
    private func whileTheReloadIsStopped(
        _ model: MessageListModel, _ source: FakePrivateMessages, _ action: @escaping @Sendable @MainActor () async -> Void
    ) async {
        let gate = CheckGate()
        source.handler = { _ async throws(ListLoadError) -> PrivateMessageListPage in
            await gate.wait()
            throw .cancelled
        }
        let running = gate.run(action)
        guard await gate.entered() else { Issue.record("The reload never asked for its page"); return }
        model.loader.cancel()
        await gate.open()
        await running.value
    }

    /// A reload that applied nothing brings nothing back (#1192): the conversation read here stays read, the badge keeps its
    /// single -1, and the ledger is not handed the page from before the reading.
    @Test func aCancelledReloadKeepsTheLocalMarks() async throws {
        let source = FakePrivateMessages()
        let recorder = SeenRecorder()
        let (model, count) = counted(source, badge: 1, recorder: recorder)
        await model.onAppear()
        let unread = try #require(model.loader.value?.threads.first)
        model.markOpened(unread, page: 1, of: 1)
        #expect(count.latest == 0)
        await whileTheReloadIsStopped(model, source) { await model.refresh() }
        #expect(!model.isUnread(unread))
        #expect(model.loader.error == nil)
        model.markOpened(unread, page: 1, of: 1)
        #expect(count.latest == 0)
        // Only the first load saw it unread.
        #expect(recorder.summaries.filter { $0.unreadThreads?.contains(10) == true }.count == 1)
    }

    /// The transport's own `.cancelled`, twice (#1191): a failure, and the conversation read here stays read (#1192).
    @Test func aReloadTheTransportCancelsKeepsTheLocalMarks() async throws {
        let source = FakePrivateMessages()
        let recorder = SeenRecorder()
        let (model, count) = counted(source, badge: 1, recorder: recorder)
        await model.onAppear()
        let unread = try #require(model.loader.value?.threads.first)
        model.markOpened(unread, page: 1, of: 1)
        source.handler = { _ async throws(ListLoadError) -> PrivateMessageListPage in throw .cancelled }
        await model.refresh()
        #expect(model.loader.error == .other)
        #expect(!model.isUnread(unread))
        #expect(count.latest == 0)
        #expect(recorder.summaries.filter { $0.unreadThreads?.contains(10) == true }.count == 1)
    }

    /// The twin for "Marquer comme non lu": the reload after HFR's confirmation applies nothing, the row stays unread.
    @Test func aCancelledReloadKeepsTheMarkedUnreadConversation() async throws {
        let source = FakePrivateMessages()
        let read = messageThread(7)
        source.handler = { _ in PrivateMessageListPage(threads: [read]) }
        let recorder = SeenRecorder()
        let (model, count) = counted(source, badge: 0, recorder: recorder)
        await model.onAppear()
        #expect(!model.isUnread(read))
        let reader = TopicReaderModel(
            target: ReaderTarget(source: .topic(TopicID(category: .privateMessages, topic: 7))), title: "", source: FakeTopicPages()
        )
        await whileTheReloadIsStopped(model, source) {
            await model.markUnreadEnded(read, in: reader, .done("Le message a été marqué comme non lu avec succès"))
        }
        #expect(model.isUnread(read))
        #expect(count.latest == 1)
        // The member's own mark unread reaches the ledger as that conversation alone (#1006), not as the stale page's set.
        #expect(recorder.summaries.allSatisfy { $0.unreadThreads?.contains(7) != true })
        #expect(recorder.marks == [7])
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
