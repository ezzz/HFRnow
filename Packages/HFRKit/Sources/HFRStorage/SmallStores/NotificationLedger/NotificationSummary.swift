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
    /// The flagged topics with unread posts for the member, each with the date of its last post. The caller passes
    /// only rows LOT-024 reads as unread (`readState == .unread`): a read row has nothing to notify, and the ledger
    /// cannot tell one from the other. A row whose last post has no date is left out, so it is
    /// never notified.
    public var flaggedTopics: [FlaggedTopicStamp]?

    /// Creates a summary; leave a part nil when the check learned nothing about it.
    public init(unreadPrivateMessages: Int? = nil, unreadThreads: Set<Int>? = nil, flaggedTopics: [FlaggedTopicStamp]? = nil) {
        self.unreadPrivateMessages = unreadPrivateMessages
        self.unreadThreads = unreadThreads
        self.flaggedTopics = flaggedTopics
    }

    /// Why the summary cannot be recorded (a negative count, a topic number not positive), or nil.
    var invalidReason: String? {
        if let count = unreadPrivateMessages, count < 0 { return "unread count \(count)" }
        if let thread = unreadThreads?.first(where: { $0 <= 0 }) { return "thread number \(thread)" }
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
