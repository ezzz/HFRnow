import Foundation
import HFRClient
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// #1006: a read or a mark unread from a list older than a background check changes that conversation of the ledger alone.
@MainActor
struct MPNotificationStaleListTests {
    /// A list loaded, then a background check that ran while the app was suspended.
    private struct Setup {
        let messages: MessageListModel
        let check: MPBackgroundCheck
        let delivery: FakeMPDelivery
        let ledger: NotificationLedgerStore
        let start: Date
    }

    private func staleList(shown: [PrivateMessageThread], checks: [MPForumReading]) async -> Setup {
        let ledger = NotificationLedgerStore(persistence: InMemorySmallStorePersistence())
        let delivery = FakeMPDelivery()
        let check = MPBackgroundCheck(
            currentAccount: { Account(pseudo: "fakeuser", isMain: true) }, ledger: ledger, settings: InMemorySettingsStore(),
            forum: FakeMPCheckForum(checks), delivery: delivery
        )
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        _ = await check.run(now: start) // the baseline, as the list loads
        let source = FakePrivateMessages()
        source.handler = { _ in PrivateMessageListPage(threads: shown) }
        let messages = MessageListModel(
            source: source, isLoggedIn: { true },
            ledgerSeen: { await MPNotificationLedger.recordSeen($0, account: "fakeuser", store: ledger) },
            ledgerThread: { await MPNotificationLedger.recordThread($0, unread: $1, account: "fakeuser", store: ledger) }
        )
        await messages.onAppear()
        _ = await check.run(now: start.addingTimeInterval(1800)) // the check that ran while the app was suspended
        return Setup(messages: messages, check: check, delivery: delivery, ledger: ledger, start: start)
    }

    /// The thread numbers of the ledger once the unstructured task of a read has reached it.
    private func unreadThreads(_ ledger: NotificationLedgerStore, expecting expected: [Int]) async -> [Int]? {
        for _ in 0..<1000 {
            if await ledger.ledger(for: "fakeuser").unreadThreads == expected { break }
            await Task.yield()
        }
        return await ledger.ledger(for: "fakeuser").unreadThreads
    }

    @Test("Reading a conversation from a list older than a background check keeps what that check recorded (#1006 a)")
    func readFromAStaleListKeepsTheCheckSLedger() async {
        let ten = messageThread(10, unread: true)
        let twelve = messageThread(12, unread: true)
        let setup = await staleList(
            shown: [ten, messageThread(12)],
            checks: [
                MPForumReading(count: 1, page: PrivateMessageListPage(threads: [ten])),
                MPForumReading(count: 2, page: PrivateMessageListPage(threads: [ten, twelve])),
                MPForumReading(count: 1, page: PrivateMessageListPage(threads: [twelve]))
            ]
        )
        #expect(await setup.delivery.delivered.map(\.topic) == [12])
        setup.messages.markOpened(ten, page: 1, of: 1)
        #expect(await unreadThreads(setup.ledger, expecting: [12]) == [12])
        _ = await setup.check.run(now: setup.start.addingTimeInterval(3600))
        #expect(await setup.delivery.delivered.map(\.topic) == [12]) // not notified a second time
    }

    @Test("Opening a conversation the stale list shows read still makes its next reply news (#1006 b)")
    func readFromAListShowingItReadStillClearsTheLedger() async {
        let ten = messageThread(10, unread: true)
        let eleven = messageThread(11, unread: true)
        let setup = await staleList(
            shown: [ten, messageThread(11)],
            checks: [
                MPForumReading(count: 1, page: PrivateMessageListPage(threads: [ten])),
                MPForumReading(count: 2, page: PrivateMessageListPage(threads: [ten, eleven])),
                MPForumReading(count: 2, page: PrivateMessageListPage(threads: [ten, eleven]))
            ]
        )
        #expect(await setup.delivery.delivered.map(\.topic) == [11])
        setup.messages.markOpened(messageThread(11), page: 1, of: 1)
        #expect(await unreadThreads(setup.ledger, expecting: [10]) == [10])
        // The member read it, the other party replied: HFR lists it unread again.
        _ = await setup.check.run(now: setup.start.addingTimeInterval(3600))
        #expect(await setup.delivery.delivered.map(\.topic) == [11, 11])
    }

    @Test("Marking a conversation unread from a stale list adds it alone and keeps what the check recorded (#1006)")
    func markUnreadFromAStaleListKeepsTheCheckSLedger() async {
        let ten = messageThread(10, unread: true)
        let twelve = messageThread(12, unread: true)
        let setup = await staleList(
            shown: [ten, messageThread(11)],
            checks: [
                MPForumReading(count: 1, page: PrivateMessageListPage(threads: [ten])),
                MPForumReading(count: 2, page: PrivateMessageListPage(threads: [ten, twelve]))
            ]
        )
        let reader = TopicReaderModel(
            target: ReaderTarget(source: .topic(TopicID(category: .privateMessages, topic: 11))), title: "", source: FakeTopicPages()
        )
        await setup.messages.markUnreadEnded(messageThread(11), in: reader, .done("Sujet marqué comme non lu"))
        #expect(await setup.ledger.ledger(for: "fakeuser").unreadThreads == [10, 11, 12])
    }
}
