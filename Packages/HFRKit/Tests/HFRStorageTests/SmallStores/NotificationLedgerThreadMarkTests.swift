import Foundation
import Testing
@testable import HFRStorage

/// #571: a reply in an already-unread conversation moves only `repliesCount` and the last-post date (HFR-PROTOCOL §6c
/// LOT-140, `R336`-`R338`), so the ledger keeps both per unread conversation.
@Suite struct NotificationLedgerThreadMarkTests {
    private static func date(_ minutes: Double) -> Date {
        SmallStoreTestSupport.date(minutes * 60)
    }

    private static func summary(_ threads: Set<Int>, marks: [UnreadThreadMark]?) -> NotificationSummary {
        NotificationSummary(unreadThreads: threads, unreadThreadMarks: marks)
    }

    private static func mark(_ topic: Int, replies: Int, at minutes: Double?) -> UnreadThreadMark {
        UnreadThreadMark(topic: topic, repliesCount: replies, lastPost: minutes.map(date))
    }

    @Test func aReplyInAnAlreadyUnreadConversationIsNews() {
        var ledger = NotificationLedger()
        ledger.record(Self.summary([5], marks: [Self.mark(5, replies: 0, at: 1)]))
        // R336 → R337: the count and the minute move, the row stays unread.
        let news = ledger.diff(summary: Self.summary([5], marks: [Self.mark(5, replies: 1, at: 2)]))
        #expect(news.newThreads == [5])
    }

    @Test func aMovedLastPostAloneOrAHigherCountAloneIsNews() {
        var ledger = NotificationLedger()
        ledger.record(Self.summary([5, 6], marks: [Self.mark(5, replies: 2, at: 1), Self.mark(6, replies: 2, at: 1)]))
        let news = ledger.diff(summary: Self.summary([5, 6], marks: [Self.mark(5, replies: 3, at: 1), Self.mark(6, replies: 2, at: 2)]))
        #expect(news.newThreads == [5, 6])
    }

    @Test func nothingMovedIsNoNewsAndRecordIsIdempotent() {
        var ledger = NotificationLedger()
        let seen = Self.summary([5], marks: [Self.mark(5, replies: 1, at: 2)])
        let first = ledger.record(seen)
        #expect(first)
        #expect(ledger.diff(summary: seen).isEmpty)
        let again = ledger.record(seen)
        #expect(!again)
    }

    @Test func aCountOrDateThatWentDownIsNotNewsAndDoesNotLowerTheBaseline() {
        var ledger = NotificationLedger()
        ledger.record(Self.summary([5], marks: [Self.mark(5, replies: 3, at: 5)]))
        // A stale list shown in the app (older than what the background check recorded).
        let lower = Self.summary([5], marks: [Self.mark(5, replies: 2, at: 4)])
        #expect(ledger.diff(summary: lower).isEmpty)
        let changed = ledger.record(lower)
        #expect(!changed)
        #expect(ledger.diff(summary: lower).isEmpty)
        #expect(ledger.diff(summary: Self.summary([5], marks: [Self.mark(5, replies: 3, at: 5)])).isEmpty)
        // A reply after a deletion still moves the date forward.
        #expect(ledger.diff(summary: Self.summary([5], marks: [Self.mark(5, replies: 3, at: 6)])).newThreads == [5])
    }

    @Test func twoMarksOfOneTopicInASummaryCountAsTheirHighest() {
        var ledger = NotificationLedger()
        ledger.record(Self.summary([5], marks: [Self.mark(5, replies: 1, at: 1)]))
        let both = Self.summary([5], marks: [Self.mark(5, replies: 2, at: 2), Self.mark(5, replies: 1, at: 1)])
        #expect(ledger.diff(summary: both).newThreads == [5])
        ledger.record(both)
        #expect(ledger.diff(summary: both).isEmpty)
    }

    @Test func aMarkForAConversationThatWasReadSinceIsIgnoredByDiff() {
        var ledger = NotificationLedger()
        ledger.record(Self.summary([5, 8], marks: [Self.mark(5, replies: 0, at: 1), Self.mark(8, replies: 0, at: 1)]))
        // 8 is not in the unread set, though its recorded mark exists and a mark for it moved forward: not news.
        let news = ledger.diff(summary: Self.summary([5], marks: [Self.mark(5, replies: 0, at: 1), Self.mark(8, replies: 4, at: 9)]))
        #expect(news.isEmpty)
    }

    @Test func recordingDropsTheMarksOfConversationsNoLongerUnread() {
        var ledger = NotificationLedger()
        ledger.record(Self.summary([5, 8], marks: [Self.mark(5, replies: 0, at: 1), Self.mark(8, replies: 0, at: 1)]))
        ledger.record(Self.summary([5], marks: [Self.mark(5, replies: 0, at: 1)]))
        #expect(ledger.unreadThreadMarks?.map(\.topic) == [5])
    }

    @Test func aNewlyUnreadAndAMovedConversationAreReportedSortedOnce() {
        var ledger = NotificationLedger()
        ledger.record(Self.summary([5, 6], marks: [Self.mark(5, replies: 0, at: 1), Self.mark(6, replies: 0, at: 1)]))
        let news = ledger.diff(summary: Self.summary(
            [9, 5, 6], marks: [Self.mark(9, replies: 0, at: 3), Self.mark(5, replies: 1, at: 2), Self.mark(6, replies: 0, at: 1)]
        ))
        #expect(news.newThreads == [5, 9])
    }

    @Test func readThenUnreadAgainIsNewsEvenWithTheSameMark() {
        var ledger = NotificationLedger()
        ledger.record(Self.summary([5], marks: [Self.mark(5, replies: 1, at: 2)]))
        ledger.record(Self.summary([], marks: []))
        #expect(ledger.diff(summary: Self.summary([5], marks: [Self.mark(5, replies: 1, at: 2)])).newThreads == [5])
    }

    @Test func anOlderRecordWithNoMarkTakesTheFirstCheckAsBaseline() throws {
        // A ledger written before #571: unread set only.
        var ledger = NotificationLedger()
        ledger.record(NotificationSummary(unreadThreads: [5]))
        let first = Self.summary([5], marks: [Self.mark(5, replies: 4, at: 9)])
        #expect(ledger.diff(summary: first).isEmpty)
        let changed = ledger.record(first)
        #expect(changed)
        #expect(ledger.diff(summary: Self.summary([5], marks: [Self.mark(5, replies: 5, at: 10)])).newThreads == [5])

        // The same document without the new key decodes, and the first check sets the baseline.
        let old = Data(#"{"unreadThreads":[5]}"#.utf8)
        var decoded = try JSONDecoder().decode(NotificationLedger.self, from: old)
        #expect(decoded.unreadThreads == [5])
        #expect(decoded.diff(summary: first).isEmpty)
        let decodedChanged = decoded.record(first)
        #expect(decodedChanged)
    }

    @Test func aSummaryWithoutMarksKeepsTheMarksAndAddsNoMovedNews() {
        var ledger = NotificationLedger()
        ledger.record(Self.summary([5], marks: [Self.mark(5, replies: 1, at: 2)]))
        let noMarks = NotificationSummary(unreadThreads: [5])
        #expect(ledger.diff(summary: noMarks).isEmpty)
        ledger.record(noMarks)
        #expect(ledger.diff(summary: Self.summary([5], marks: [Self.mark(5, replies: 2, at: 3)])).newThreads == [5])
    }

    @Test func aMarkForAThreadThatIsNotUnreadIsIgnoredAndAMissingDateStillCountsReplies() {
        var ledger = NotificationLedger()
        ledger.record(Self.summary([5], marks: [Self.mark(5, replies: 1, at: nil)]))
        let moved = Self.summary([5], marks: [Self.mark(5, replies: 2, at: nil), Self.mark(8, replies: 9, at: 9)])
        #expect(ledger.diff(summary: moved).newThreads == [5])
        ledger.record(Self.summary([5], marks: [Self.mark(8, replies: 9, at: 9)]))
        #expect(ledger.unreadThreadMarks?.map(\.topic) == [5])
    }

    @Test func anInvalidMarkIsNeitherNewsNorRecorded() {
        var ledger = NotificationLedger()
        let bad = Self.summary([5], marks: [Self.mark(5, replies: -1, at: 1)])
        #expect(bad.invalidReason != nil)
        #expect(ledger.diff(summary: bad).isEmpty)
        let recorded = ledger.record(bad)
        #expect(!recorded)
    }
}
