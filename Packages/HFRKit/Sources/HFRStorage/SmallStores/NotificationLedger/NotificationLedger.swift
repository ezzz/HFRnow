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
    /// The unread conversations last recorded; nil when none were.
    public private(set) var unreadThreads: Set<Int>?
    /// The latest last post recorded per flagged topic, latest first; nil when no flags list was recorded.
    public private(set) var flaggedTopics: [FlaggedTopicStamp]?
    /// When the account was last checked; nil when it never was.
    public private(set) var lastCheck: Date?

    /// An empty ledger: nothing notified, never checked.
    public init() {}

    /// What `summary` holds that this ledger has not recorded.
    public func diff(summary: NotificationSummary) -> NotificationNews {
        var news = NotificationNews()
        if let count = summary.unreadPrivateMessages {
            news.newPrivateMessages = max(0, count - (unreadPrivateMessages ?? 0))
        }
        if let threads = summary.unreadThreads, let known = unreadThreads {
            news.newThreads = threads.subtracting(known).sorted()
        }
        if let stamps = summary.flaggedTopics, let known = flaggedTopics {
            let notified = Self.latest(known)
            news.topics = Self.latestPerTopic(stamps).filter { stamp in
                notified[stamp.topic].map { stamp.lastPost > $0 } ?? true
            }
        }
        return news
    }

    /// Records `summary` as notified: its count and conversations replace the stored ones (a count that went down is
    /// the new baseline, as legacy stored every count it read), each flagged topic keeps its latest last post. Parts
    /// the summary leaves nil are kept. Idempotent; returns false when nothing changed.
    @discardableResult
    public mutating func record(_ summary: NotificationSummary) -> Bool {
        let before = self
        if let count = summary.unreadPrivateMessages {
            unreadPrivateMessages = count
        }
        if let threads = summary.unreadThreads {
            unreadThreads = threads
        }
        if let stamps = summary.flaggedTopics {
            var latest = Self.latest(flaggedTopics ?? [])
            for stamp in stamps {
                latest[stamp.topic] = max(latest[stamp.topic] ?? stamp.lastPost, stamp.lastPost)
            }
            flaggedTopics = Self.kept(latest)
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

    /// The `topicLimit` latest stamps, latest first, ties by category then topic number so the order is stable.
    private static func kept(_ latest: [TopicID: Date]) -> [FlaggedTopicStamp] {
        let stamps = latest.map { FlaggedTopicStamp(topic: $0.key, lastPost: $0.value) }.sorted { lhs, rhs in
            if lhs.lastPost != rhs.lastPost { return lhs.lastPost > rhs.lastPost }
            let left = rank(of: lhs.topic.category)
            let right = rank(of: rhs.topic.category)
            return left == right ? lhs.topic.topic < rhs.topic.topic : left < right
        }
        return Array(stamps.prefix(topicLimit))
    }

    private static func rank(of category: CategoryID) -> (Int, Int) {
        switch category {
        case .forum(let number): (0, number)
        case .privateMessages: (1, 0)
        }
    }
}
