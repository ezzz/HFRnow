import Foundation
import HFRModels

/// What one account was last notified of, and when it was last checked (LOT-091, FEAT-005 proposed by Bybifok).
///
/// Legacy kept one global count (`nb_mp`) and notified when a check read a higher one (`MPBackgroundService.swift:93-101`
/// on `origin/master` at `21173e77`, ObjC `HFRplusAppDelegate.m:251-266`), whatever the account. Here each account has
/// its ledger: the unread count (same rule, the count last recorded is the baseline), the unread conversations and the
/// last post of each flagged topic. A part never recorded is a baseline for conversations and flags (the first check
/// notifies nothing), and 0 for the count, as legacy's `integerForKey` default. A pure value: `NotificationLedgerStore`
/// keeps one per account.
public struct NotificationLedger: Sendable, Hashable, Codable {
    /// The number of flagged topics kept; recording more drops the ones whose last post is the oldest.
    public static let topicLimit = 500

    /// The unread count last recorded; nil when none was.
    public private(set) var unreadPrivateMessages: Int?
    /// The unread conversations last recorded, sorted; nil when none were.
    public private(set) var unreadThreads: [Int]?
    /// The latest last post recorded per flagged topic, latest first; nil when no flags list was recorded.
    public private(set) var flaggedTopics: [FlaggedTopicStamp]?
    /// The latest last post among the topics dropped by `topicLimit`: a topic not recorded is news only after it, so a
    /// dropped topic listed again unchanged is not notified again. Nil while none was dropped.
    public private(set) var flagWatermark: Date?
    /// When the account was last checked; nil when it never was.
    public private(set) var lastCheck: Date?

    /// An empty ledger: nothing notified, never checked.
    public init() {}

    /// What `summary` holds that this ledger has not recorded. An invalid summary (see `record`) is no news.
    public func diff(summary: NotificationSummary) -> NotificationNews {
        var news = NotificationNews()
        guard summary.invalidReason == nil else { return news }
        if let count = summary.unreadPrivateMessages {
            news.newPrivateMessages = max(0, count - max(0, unreadPrivateMessages ?? 0))
        }
        if let threads = summary.unreadThreads, let known = unreadThreads {
            news.newThreads = threads.subtracting(known).sorted()
        }
        if let stamps = summary.flaggedTopics, let known = flaggedTopics {
            let notified = Self.latest(known)
            news.topics = Self.latestPerTopic(stamps).filter { stamp in
                if let recorded = notified[stamp.topic] { return stamp.lastPost > recorded }
                return flagWatermark.map { stamp.lastPost > $0 } ?? true
            }
        }
        return news
    }

    /// Records `summary` as notified: its count and conversations replace the stored ones (a count that went down is
    /// the new baseline, as legacy stored every count it read), each flagged topic keeps its latest last post. Parts
    /// the summary leaves nil are kept. Idempotent; returns false when nothing changed. A summary with a negative count
    /// or a topic number not positive is not recorded (`NotificationLedgerStore` throws for it).
    @discardableResult
    public mutating func record(_ summary: NotificationSummary) -> Bool {
        guard summary.invalidReason == nil else { return false }
        let before = self
        if let count = summary.unreadPrivateMessages {
            unreadPrivateMessages = count
        }
        if let threads = summary.unreadThreads {
            unreadThreads = threads.sorted()
        }
        if let stamps = summary.flaggedTopics {
            var latest = Self.latest(flaggedTopics ?? [])
            for stamp in stamps {
                latest[stamp.topic] = max(latest[stamp.topic] ?? stamp.lastPost, stamp.lastPost)
            }
            let ordered = latest.map { FlaggedTopicStamp(topic: $0.key, lastPost: $0.value) }.sorted(by: Self.latestFirst)
            flaggedTopics = Array(ordered.prefix(Self.topicLimit))
            if let dropped = ordered.dropFirst(Self.topicLimit).first?.lastPost {
                flagWatermark = max(flagWatermark ?? dropped, dropped)
            }
        }
        return self != before
    }

    /// Whether a check may run at `now`: never checked, at least `minimumInterval` since the last check, or a last
    /// check in the future (the clock went back), which would otherwise block checks until the clock catches up.
    public func isDue(now: Date, minimumInterval: TimeInterval) -> Bool {
        guard let lastCheck, lastCheck <= now else { return true }
        return now.timeIntervalSince(lastCheck) >= max(0, minimumInterval)
    }

    /// Records a check at `date`, whatever it found (a failed request counts towards the interval too). Returns false
    /// when that date is already the last check.
    @discardableResult
    public mutating func markChecked(at date: Date) -> Bool {
        guard lastCheck != date else { return false }
        lastCheck = date
        return true
    }

    // MARK: Internals

    private static func latest(_ stamps: [FlaggedTopicStamp]) -> [TopicID: Date] {
        stamps.reduce(into: [:]) { latest, stamp in
            latest[stamp.topic] = max(latest[stamp.topic] ?? stamp.lastPost, stamp.lastPost)
        }
    }

    /// One stamp per topic, the latest, where the topic first appears.
    private static func latestPerTopic(_ stamps: [FlaggedTopicStamp]) -> [FlaggedTopicStamp] {
        let latest = latest(stamps)
        var seen = Set<TopicID>()
        return stamps.compactMap { stamp in
            guard seen.insert(stamp.topic).inserted, let date = latest[stamp.topic] else { return nil }
            return FlaggedTopicStamp(topic: stamp.topic, lastPost: date)
        }
    }

    /// Latest last post first, ties in the small stores' topic order so the saved order is stable.
    private static func latestFirst(_ lhs: FlaggedTopicStamp, _ rhs: FlaggedTopicStamp) -> Bool {
        lhs.lastPost == rhs.lastPost ? TopicOrder.precedes(lhs.topic, rhs.topic) : lhs.lastPost > rhs.lastPost
    }
}
