import Foundation
import HFRModels

/// What one background check saw for one account, as the notification ledger reads it (LOT-091).
///
/// A nil part is "no information" (LOT-047's contract: a logged-out or unrecognised answer is never 0): it yields no
/// news and is not recorded, so the next check compares with what was last known.
public struct NotificationSummary: Sendable, Hashable {
    /// The unread private messages count of the forum header (LOT-047).
    public var unreadPrivateMessages: Int?
    /// The topic numbers of the unread private conversations, when the check read the list.
    public var unreadThreads: Set<Int>?
    /// For the unread conversations, their reply count and last-post date as the list row prints them (#571): a reply in
    /// a conversation that is already unread moves only these (HFR-PROTOCOL §6c LOT-140, `R336`-`R338`). Marks of a
    /// conversation not in `unreadThreads` are ignored; nil when the check has none (the set alone is then compared).
    public var unreadThreadMarks: [UnreadThreadMark]?
    /// The flagged topics, each with the date of its last post. A row the caller has evidence the member already read
    /// has nothing to notify and may be left out; the flags page gives no such evidence today (LOT-024 reads every row
    /// as `.unknown`, pending capture), so the date rule of `NotificationLedger` is the only de-duplication. A row
    /// whose last post has no date is left out, so it is never notified.
    public var flaggedTopics: [FlaggedTopicStamp]?

    /// Creates a summary; leave a part nil when the check learned nothing about it.
    public init(unreadPrivateMessages: Int? = nil, unreadThreads: Set<Int>? = nil,
                unreadThreadMarks: [UnreadThreadMark]? = nil, flaggedTopics: [FlaggedTopicStamp]? = nil) {
        self.unreadPrivateMessages = unreadPrivateMessages
        self.unreadThreads = unreadThreads
        self.unreadThreadMarks = unreadThreadMarks
        self.flaggedTopics = flaggedTopics
    }

    /// Why the summary cannot be recorded (a negative count, a topic number not positive), or nil.
    var invalidReason: String? {
        if let count = unreadPrivateMessages, count < 0 { return "unread count \(count)" }
        if let thread = unreadThreads?.first(where: { $0 <= 0 }) { return "thread number \(thread)" }
        if let mark = unreadThreadMarks?.first(where: { $0.topic <= 0 || $0.repliesCount < 0 }) {
            return "thread mark \(mark.topic)"
        }
        if let stamp = flaggedTopics?.first(where: { $0.topic.topic <= 0 }) { return "topic number \(stamp.topic.topic)" }
        return nil
    }
}

/// A flagged topic and the date of its last post: the topic has news when that date is later than the one notified.
public struct FlaggedTopicStamp: Sendable, Hashable, Codable {
    /// The topic.
    public var topic: TopicID
    /// The date of its last post, as the flags list prints it (to the minute).
    public var lastPost: Date

    /// Creates a stamp.
    public init(topic: TopicID, lastPost: Date) {
        self.topic = topic
        self.lastPost = lastPost
    }
}

/// An unread private conversation and what its list row says about its latest message: a conversation has news again
/// when its reply count or its last-post date grows (#571).
public struct UnreadThreadMark: Sendable, Hashable, Codable {
    /// The conversation's topic number.
    public var topic: Int
    /// Its reply count (the first message is not counted).
    public var repliesCount: Int
    /// The date of its last post, to the minute; nil when the row prints none.
    public var lastPost: Date?

    /// Creates a mark.
    public init(topic: Int, repliesCount: Int, lastPost: Date?) {
        self.topic = topic
        self.repliesCount = repliesCount
        self.lastPost = lastPost
    }

    /// Whether `self`, read now, is later than `recorded`: more replies or a later last post.
    func movedForward(from recorded: Self) -> Bool {
        if repliesCount > recorded.repliesCount { return true }
        guard let now = lastPost, let before = recorded.lastPost else { return false }
        return now > before
    }
}
