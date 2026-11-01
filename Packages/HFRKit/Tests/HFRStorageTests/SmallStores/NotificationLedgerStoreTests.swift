import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// The ledger store: one ledger per account key, validated writes, account removal, persistence.
@Suite struct NotificationLedgerStoreTests {
    static let pizza = TopicID(category: .forum(13), topic: 28563)

    private static func makeStore() -> (NotificationLedgerStore, InMemorySmallStorePersistence<NotificationLedgerDocument>) {
        let persistence = InMemorySmallStorePersistence<NotificationLedgerDocument>()
        return (NotificationLedgerStore(persistence: persistence), persistence)
    }

    @Test func ledgersAreKeptPerAccountKey() async throws {
        let (store, persistence) = Self.makeStore()
        #expect(try await store.record(NotificationSummary(unreadPrivateMessages: 2), account: "Ali\u{200B}ce"))
        #expect(await store.ledger(for: "alice").unreadPrivateMessages == 2)
        #expect(await store.ledger(for: "ALICE").unreadPrivateMessages == 2)
        #expect(await store.ledger(for: "bob") == NotificationLedger())
        #expect(persistence.document.map { Array($0.accounts.keys) } == ["alice"])
        #expect(await store.ledger(for: "bob").diff(summary: NotificationSummary(unreadPrivateMessages: 2)).newPrivateMessages == 2)
    }

    @Test func recordNewsReturnsEachNewsOnce() async throws {
        let (store, _) = Self.makeStore()
        let summary = NotificationSummary(unreadPrivateMessages: 2)
        #expect(try await store.recordNews(summary, account: "user1").newPrivateMessages == 2)
        #expect(try await store.recordNews(summary, account: "User1").isEmpty)
        #expect(try await store.recordNews(NotificationSummary(unreadPrivateMessages: 3), account: "user1").newPrivateMessages == 1)
        await #expect(throws: SmallStoreError.self) {
            try await store.recordNews(NotificationSummary(unreadPrivateMessages: -1), account: "user1")
        }
    }

    @Test func overlappingChecksGetTheNewsAndTheTurnOnce() async throws {
        let (store, _) = Self.makeStore()
        let summary = NotificationSummary(unreadPrivateMessages: 1)
        async let first = store.recordNews(summary, account: "user1")
        async let second = store.recordNews(summary, account: "user1")
        #expect(try await [first, second].map(\.newPrivateMessages).sorted() == [0, 1])
        let now = SmallStoreTestSupport.date(0)
        async let turnA = store.markCheckedIfDue(account: "user1", now: now, minimumInterval: 600)
        async let turnB = store.markCheckedIfDue(account: "user1", now: now, minimumInterval: 600)
        #expect(try await [turnA, turnB].sorted { !$0 && $1 } == [false, true])
    }

    @Test func markCheckedIfDueRespectsTheInterval() async throws {
        let (store, persistence) = Self.makeStore()
        #expect(try await store.markCheckedIfDue(account: "user1", now: SmallStoreTestSupport.date(0), minimumInterval: 600))
        #expect(try await !store.markCheckedIfDue(account: "user1", now: SmallStoreTestSupport.date(599), minimumInterval: 600))
        #expect(await store.ledger(for: "user1").lastCheck == SmallStoreTestSupport.date(0))
        #expect(try await store.markCheckedIfDue(account: "user1", now: SmallStoreTestSupport.date(600), minimumInterval: 600))
        #expect(persistence.document?.accounts["user1"]?.lastCheck == SmallStoreTestSupport.date(600))
    }

    @Test func aSecondRecordOfTheSameSummarySavesNothing() async throws {
        let persistence = FailingSmallStorePersistence<NotificationLedgerDocument>()
        let store = NotificationLedgerStore(persistence: persistence)
        let summary = NotificationSummary(unreadPrivateMessages: 1, flaggedTopics: [FlaggedTopicStamp(topic: Self.pizza, lastPost: .now)])
        #expect(try await store.record(summary, account: "user1"))
        #expect(try await !store.record(summary, account: "User1"))
        #expect(try await store.markChecked(account: "user1", at: SmallStoreTestSupport.date(1)))
        #expect(try await !store.markChecked(account: "user1", at: SmallStoreTestSupport.date(1)))
        #expect(persistence.saveCount == 2)
    }

    @Test(
        "A negative count or a topic number not positive is refused and nothing is saved",
        arguments: [
            NotificationSummary(unreadPrivateMessages: -1),
            NotificationSummary(unreadThreads: [3, 0]),
            NotificationSummary(flaggedTopics: [FlaggedTopicStamp(topic: TopicID(category: .forum(13), topic: 0), lastPost: .now)])
        ]
    )
    func invalidSummariesAreRefused(summary: NotificationSummary) async {
        let (store, persistence) = Self.makeStore()
        await #expect(throws: SmallStoreError.self) { try await store.record(summary, account: "user1") }
        #expect(persistence.document == nil)
    }

    @Test func anEmptyAccountIsRefused() async {
        let (store, persistence) = Self.makeStore()
        await #expect(throws: SmallStoreError.emptyAccount) { try await store.record(NotificationSummary(), account: "\u{200B}") }
        await #expect(throws: SmallStoreError.emptyAccount) { try await store.markChecked(account: "", at: .now) }
        await #expect(throws: SmallStoreError.emptyAccount) { try await store.removeAccount("") }
        #expect(persistence.document == nil)
    }

    @Test func removingAnAccountDropsOnlyItsLedger() async throws {
        let (store, persistence) = Self.makeStore()
        try await store.record(NotificationSummary(unreadPrivateMessages: 4), account: "user1")
        try await store.markChecked(account: "user2", at: SmallStoreTestSupport.date(1))
        #expect(try await store.removeAccount("USER1"))
        #expect(try await !store.removeAccount("user1"))
        #expect(await store.ledger(for: "user1") == NotificationLedger())
        #expect(await store.ledger(for: "user2").lastCheck == SmallStoreTestSupport.date(1))
        #expect(persistence.document.map { Array($0.accounts.keys) } == ["user2"])
    }

    @Test func aLedgerSurvivesAReopenedFileExactly() async throws {
        let directory = try SmallStoreTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "notifications.json")
        let summary = NotificationSummary(
            unreadPrivateMessages: 3, unreadThreads: [7, 5],
            flaggedTopics: [FlaggedTopicStamp(topic: Self.pizza, lastPost: SmallStoreTestSupport.date(2))]
        )
        let store = NotificationLedgerStore(persistence: FileSmallStorePersistence(fileURL: file))
        try await store.record(summary, account: "user1")
        try await store.markChecked(account: "user1", at: SmallStoreTestSupport.date(3))
        let reopened = NotificationLedgerStore(persistence: FileSmallStorePersistence(fileURL: file))
        #expect(await reopened.ledger(for: "user1") == store.ledger(for: "user1"))
        #expect(await reopened.ledger(for: "user1").lastCheck == SmallStoreTestSupport.date(3))
        #expect(await reopened.ledger(for: "user1").diff(summary: summary).isEmpty)
    }

    @Test func anUnreadableStoreAnswersAnEmptyLedgerAndRefusesWrites() async {
        let persistence = FailingSmallStorePersistence<NotificationLedgerDocument>(
            NotificationLedgerDocument(accounts: ["user1": NotificationLedger()])
        )
        persistence.failsToLoad = true
        let store = NotificationLedgerStore(persistence: persistence)
        #expect(await store.ledger(for: "user1") == NotificationLedger())
        #expect(await store.loadFailure() != nil)
        await #expect(throws: SmallStoreError.self) {
            try await store.record(NotificationSummary(unreadPrivateMessages: 1), account: "user1")
        }
        await #expect(throws: SmallStoreError.self) { try await store.removeAccount("user1") }
        #expect(persistence.saveCount == 0)
    }
}
