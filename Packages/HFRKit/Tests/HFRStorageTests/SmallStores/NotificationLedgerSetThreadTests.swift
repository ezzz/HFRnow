import Foundation
import Testing
@testable import HFRStorage

/// #1006: a conversation read or marked unread in the app changes that conversation alone; a list shown from before a
/// background check never replaces the recorded set.
@Suite struct NotificationLedgerSetThreadTests {
    private static func mark(_ topic: Int, replies: Int, at minutes: Double) -> UnreadThreadMark {
        UnreadThreadMark(topic: topic, repliesCount: replies, lastPost: SmallStoreTestSupport.date(minutes * 60))
    }

    private static func ledger(_ threads: Set<Int>, marks: [UnreadThreadMark]? = nil) -> NotificationLedger {
        var ledger = NotificationLedger()
        ledger.record(NotificationSummary(unreadThreads: threads, unreadThreadMarks: marks))
        return ledger
    }

    @Test func readingOneConversationKeepsTheOthersTheBackgroundCheckRecorded() {
        // The stale list showed Z; the background check recorded X meanwhile (scenario a).
        var ledger = Self.ledger([1, 2], marks: [Self.mark(1, replies: 0, at: 1), Self.mark(2, replies: 0, at: 1)])
        let r1 = ledger.setThread(1, unread: nil)
        #expect(r1)
        #expect(ledger.unreadThreads == [2])
        #expect(ledger.unreadThreadMarks?.map(\.topic) == [2])
        #expect(ledger.diff(summary: NotificationSummary(unreadThreads: [2])).isEmpty)
    }

    @Test func aConversationTheLedgerHoldsIsNewsAgainAfterItIsReadEvenIfTheListShowedItRead() {
        // Scenario b: X was in the ledger, the stale list showed it read, the member opens it.
        var ledger = Self.ledger([7], marks: [Self.mark(7, replies: 3, at: 5)])
        let r2 = ledger.setThread(7, unread: nil)
        #expect(r2)
        let reply = NotificationSummary(unreadThreads: [7], unreadThreadMarks: [Self.mark(7, replies: 4, at: 6)])
        #expect(ledger.diff(summary: reply).newThreads == [7])
    }

    @Test func markingOneConversationUnreadAddsItAloneWithoutNews() {
        var ledger = Self.ledger([2], marks: [Self.mark(2, replies: 1, at: 1)])
        let mark = Self.mark(9, replies: 4, at: 3)
        let r3 = ledger.setThread(9, unread: mark)
        #expect(r3)
        #expect(ledger.unreadThreads == [2, 9])
        #expect(ledger.diff(summary: NotificationSummary(unreadThreads: [2, 9], unreadThreadMarks: [mark])).isEmpty)
        let r4 = ledger.setThread(9, unread: mark)
        #expect(!r4) // idempotent
    }

    @Test func aLowerMarkDoesNotLowerTheBaseline() {
        var ledger = Self.ledger([9], marks: [Self.mark(9, replies: 5, at: 5)])
        let r5 = ledger.setThread(9, unread: Self.mark(9, replies: 4, at: 4))
        #expect(!r5)
        #expect(ledger.unreadThreadMarks == [Self.mark(9, replies: 5, at: 5)])
    }

    @Test func nothingChangesWithoutARecordedSetOrForAnInvalidTopic() {
        var empty = NotificationLedger()
        let r6 = empty.setThread(3, unread: nil)
        #expect(!r6)
        let r7 = empty.setThread(3, unread: Self.mark(3, replies: 0, at: 1))
        #expect(!r7)
        #expect(empty == NotificationLedger())
        var ledger = Self.ledger([3])
        let r8 = ledger.setThread(0, unread: nil)
        #expect(!r8)
        let r9 = ledger.setThread(3, unread: Self.mark(4, replies: 0, at: 1))
        #expect(!r9) // a mark of another topic
        let r10 = ledger.setThread(5, unread: nil)
        #expect(!r10) // not in the set
    }

    @Test func theStoreAppliesItInOneStepAndRefusesInvalidValues() async throws {
        let store = NotificationLedgerStore(persistence: InMemorySmallStorePersistence<NotificationLedgerDocument>())
        try await store.record(NotificationSummary(unreadThreads: [1, 2]), account: "Alice")
        #expect(try await store.setThread(1, unread: nil, account: "alice")) // same account key
        #expect(await store.ledger(for: "Alice").unreadThreads == [2])
        await #expect(throws: SmallStoreError.self) { try await store.setThread(0, unread: nil, account: "Alice") }
    }
}
