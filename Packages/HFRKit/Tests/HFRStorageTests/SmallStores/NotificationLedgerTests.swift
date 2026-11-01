import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// The ledger value: legacy's count rule (`MPBackgroundService.swift:93-101`), conversations and flags, the interval.
@Suite struct NotificationLedgerTests {
    static let pizza = TopicID(category: .forum(13), topic: 28563)
    static let cuisine = TopicID(category: .forum(13), topic: 101586)
    static let hardware = TopicID(category: .forum(1), topic: 42)

    private static func date(_ minutes: Double) -> Date {
        SmallStoreTestSupport.date(minutes * 60)
    }

    private static func stamp(_ topic: TopicID, _ minutes: Double) -> FlaggedTopicStamp {
        FlaggedTopicStamp(topic: topic, lastPost: date(minutes))
    }

    @Test func aHigherCountIsNewsAndTheCountRecordedIsTheBaseline() {
        var ledger = NotificationLedger()
        // Never recorded: the baseline is 0, as legacy's `integerForKey` default.
        #expect(ledger.diff(summary: NotificationSummary(unreadPrivateMessages: 2)).newPrivateMessages == 2)
        let recorded = ledger.record(NotificationSummary(unreadPrivateMessages: 2))
        #expect(recorded)
        #expect(ledger.diff(summary: NotificationSummary(unreadPrivateMessages: 2)).isEmpty)
        #expect(ledger.diff(summary: NotificationSummary(unreadPrivateMessages: 3)).newPrivateMessages == 1)
        // A count that went down (MPs read) is the new baseline: the next rise is news again.
        ledger.record(NotificationSummary(unreadPrivateMessages: 1))
        #expect(ledger.diff(summary: NotificationSummary(unreadPrivateMessages: 2)).newPrivateMessages == 1)
        #expect(ledger.diff(summary: NotificationSummary(unreadPrivateMessages: 0)).isEmpty)
    }

    @Test func aCountAboveAThousandIsNotNewsAgain() {
        // Legacy reset a stored count above 1000 to 0 (`MPBackgroundService.swift:94`), so it notified at every check.
        var ledger = NotificationLedger()
        ledger.record(NotificationSummary(unreadPrivateMessages: 1_500))
        #expect(ledger.diff(summary: NotificationSummary(unreadPrivateMessages: 1_500)).isEmpty)
    }

    @Test func conversationsUnreadSinceTheLastRecordAreNews() {
        var ledger = NotificationLedger()
        // Never recorded: a baseline, nothing is news.
        #expect(ledger.diff(summary: NotificationSummary(unreadThreads: [5])).isEmpty)
        ledger.record(NotificationSummary(unreadThreads: [5, 6]))
        #expect(ledger.diff(summary: NotificationSummary(unreadThreads: [5, 6, 9, 7])).newThreads == [7, 9])
        // Read since, unread again: news again.
        ledger.record(NotificationSummary(unreadThreads: [6]))
        #expect(ledger.diff(summary: NotificationSummary(unreadThreads: [5, 6])).newThreads == [5])
    }

    @Test func aFlaggedTopicWithALaterLastPostIsNews() {
        var ledger = NotificationLedger()
        #expect(ledger.diff(summary: NotificationSummary(flaggedTopics: [Self.stamp(Self.pizza, 1)])).isEmpty)
        ledger.record(NotificationSummary(flaggedTopics: [Self.stamp(Self.pizza, 1), Self.stamp(Self.cuisine, 1)]))
        let summary = NotificationSummary(flaggedTopics: [
            Self.stamp(Self.cuisine, 1), Self.stamp(Self.pizza, 2), Self.stamp(Self.hardware, 0)
        ])
        #expect(ledger.diff(summary: summary).topics == [Self.stamp(Self.pizza, 2), Self.stamp(Self.hardware, 0)])
        // A last post older than the one recorded (a deleted post) is not news, and does not move the record back.
        ledger.record(NotificationSummary(flaggedTopics: [Self.stamp(Self.pizza, 0)]))
        #expect(ledger.flaggedTopics?.first { $0.topic == Self.pizza }?.lastPost == Self.date(1))
        #expect(ledger.diff(summary: NotificationSummary(flaggedTopics: [Self.stamp(Self.pizza, 1)])).isEmpty)
    }

    @Test func aTopicListedTwiceIsOneNewsAtItsLatestLastPost() {
        var ledger = NotificationLedger()
        ledger.record(NotificationSummary(flaggedTopics: []))
        let summary = NotificationSummary(
            flaggedTopics: [Self.stamp(Self.pizza, 1), Self.stamp(Self.hardware, 1), Self.stamp(Self.pizza, 3)]
        )
        #expect(ledger.diff(summary: summary).topics == [Self.stamp(Self.pizza, 3), Self.stamp(Self.hardware, 1)])
    }

    @Test func recordIsIdempotentAndAnAbsentPartIsNeitherNewsNorRecorded() {
        var ledger = NotificationLedger()
        let summary = NotificationSummary(
            unreadPrivateMessages: 3, unreadThreads: [5], flaggedTopics: [Self.stamp(Self.pizza, 1), Self.stamp(Self.pizza, 2)]
        )
        let first = ledger.record(summary)
        #expect(first)
        let recorded = ledger
        let second = ledger.record(summary)
        #expect(!second)
        #expect(ledger == recorded)
        #expect(ledger.diff(summary: summary).isEmpty)
        // No information (a logged-out check, LOT-047): no news, nothing recorded.
        #expect(ledger.diff(summary: NotificationSummary()).isEmpty)
        let absent = ledger.record(NotificationSummary())
        #expect(!absent)
        #expect(ledger == recorded)
        #expect(ledger.unreadPrivateMessages == 3)
    }

    @Test func theOldestFlaggedTopicsAreDroppedBeyondTheLimit() {
        var ledger = NotificationLedger()
        let stamps = (1...(NotificationLedger.topicLimit + 1)).map { Self.stamp(TopicID(category: .forum(13), topic: $0), Double($0)) }
        ledger.record(NotificationSummary(flaggedTopics: stamps))
        #expect(ledger.flaggedTopics?.count == NotificationLedger.topicLimit)
        #expect(ledger.flaggedTopics?.first == stamps.last)
        // The dropped topic is news again; the kept ones are not.
        #expect(ledger.diff(summary: NotificationSummary(flaggedTopics: [stamps[0], stamps[1]])).topics == [stamps[0]])
    }

    /// A last check (seconds, nil for never), the time of the question, the minimum interval, the answer.
    struct DueCase: Sendable {
        let lastCheck: Double?
        let now: Double
        let interval: Double
        let due: Bool
    }

    @Test(
        "Due when never checked, at or past the interval, or when the last check is in the future",
        arguments: [
            DueCase(lastCheck: nil, now: 0, interval: 600, due: true),
            DueCase(lastCheck: 0, now: 600, interval: 600, due: true),
            DueCase(lastCheck: 0, now: 599.999, interval: 600, due: false),
            DueCase(lastCheck: 0, now: 0, interval: 600, due: false),
            DueCase(lastCheck: 600, now: 0, interval: 600, due: true),
            DueCase(lastCheck: 0, now: 0, interval: -1, due: true)
        ]
    )
    func isDue(dueCase: DueCase) {
        var ledger = NotificationLedger()
        if let lastCheck = dueCase.lastCheck { ledger.markChecked(at: SmallStoreTestSupport.date(lastCheck)) }
        #expect(ledger.isDue(now: SmallStoreTestSupport.date(dueCase.now), minimumInterval: dueCase.interval) == dueCase.due)
    }

    @Test func markCheckedReportsAChange() {
        var ledger = NotificationLedger()
        let first = ledger.markChecked(at: SmallStoreTestSupport.date(1))
        #expect(first)
        let same = ledger.markChecked(at: SmallStoreTestSupport.date(1))
        #expect(!same)
        let earlier = ledger.markChecked(at: SmallStoreTestSupport.date(0))
        #expect(earlier)
        #expect(ledger.lastCheck == SmallStoreTestSupport.date(0))
    }
}
