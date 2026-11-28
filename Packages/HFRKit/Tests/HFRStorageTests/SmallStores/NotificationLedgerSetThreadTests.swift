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
        let changed = ledger.setThread(1, unread: nil)
        #expect(changed)
        #expect(ledger.unreadThreads == [2])
        #expect(ledger.unreadThreadMarks?.map(\.topic) == [2])
        #expect(ledger.diff(summary: NotificationSummary(unreadThreads: [2])).isEmpty)
    }

    @Test func aConversationTheLedgerHoldsIsNewsAgainAfterItIsReadEvenIfTheListShowedItRead() {
        // Scenario b: X was in the ledger, the stale list showed it read, the member opens it.
        var ledger = Self.ledger([7], marks: [Self.mark(7, replies: 3, at: 5)])
        let read = ledger.setThread(7, unread: nil)
        #expect(read)
        let reply = NotificationSummary(unreadThreads: [7], unreadThreadMarks: [Self.mark(7, replies: 4, at: 6)])
        #expect(ledger.diff(summary: reply).newThreads == [7])
    }

    @Test func markingOneConversationUnreadAddsItAloneWithoutNews() {
        var ledger = Self.ledger([2], marks: [Self.mark(2, replies: 1, at: 1)])
        let mark = Self.mark(9, replies: 4, at: 3)
        let added = ledger.setThread(9, unread: mark)
        #expect(added)
        #expect(ledger.unreadThreads == [2, 9])
        #expect(ledger.diff(summary: NotificationSummary(unreadThreads: [2, 9], unreadThreadMarks: [mark])).isEmpty)
        let repeated = ledger.setThread(9, unread: mark)
        #expect(!repeated) // idempotent
    }

    @Test func aLowerMarkDoesNotLowerTheBaseline() {
        var ledger = Self.ledger([9], marks: [Self.mark(9, replies: 5, at: 5)])
        let lowered = ledger.setThread(9, unread: Self.mark(9, replies: 4, at: 4))
        #expect(!lowered)
        #expect(ledger.unreadThreadMarks == [Self.mark(9, replies: 5, at: 5)])
    }

    @Test func nothingChangesWithoutARecordedSetOrForAnInvalidTopic() {
        var empty = NotificationLedger()
        let noSetRead = empty.setThread(3, unread: nil)
        #expect(!noSetRead)
        let noSetAdd = empty.setThread(3, unread: Self.mark(3, replies: 0, at: 1))
        #expect(!noSetAdd)
        #expect(empty == NotificationLedger())
        var ledger = Self.ledger([3])
        let invalidTopic = ledger.setThread(0, unread: nil)
        #expect(!invalidTopic)
        let otherTopic = ledger.setThread(3, unread: Self.mark(4, replies: 0, at: 1))
        #expect(!otherTopic) // a mark of another topic
        let notInSet = ledger.setThread(5, unread: nil)
        #expect(!notInSet) // not in the set
    }

    @Test func theStoreAppliesItInOneStepAndRefusesInvalidValues() async throws {
        let store = NotificationLedgerStore(persistence: InMemorySmallStorePersistence<NotificationLedgerDocument>())
        try await store.record(NotificationSummary(unreadThreads: [1, 2]), account: "Alice")
        #expect(try await store.setThread(1, unread: nil, account: "alice")) // same account key
        #expect(await store.ledger(for: "Alice").unreadThreads == [2])
        await #expect(throws: SmallStoreError.self) { try await store.setThread(0, unread: nil, account: "Alice") }
        let other = UnreadThreadMark(topic: 4, repliesCount: 0, lastPost: nil)
        await #expect(throws: SmallStoreError.self) { try await store.setThread(3, unread: other, account: "Alice") }
    }
}
