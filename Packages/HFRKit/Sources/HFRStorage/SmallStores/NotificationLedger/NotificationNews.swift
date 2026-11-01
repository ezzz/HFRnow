/// What a check found that was not notified yet (LOT-091).
public struct NotificationNews: Sendable, Hashable {
    /// How many more unread private messages than the count last recorded; 0 when there are not more.
    public var newPrivateMessages: Int
    /// Unread private conversations not unread at the last record, by topic number.
    public var newThreads: [Int]
    /// Flagged topics whose last post is later than the one recorded, in the summary's order.
    public var topics: [FlaggedTopicStamp]

    /// Creates news.
    public init(newPrivateMessages: Int = 0, newThreads: [Int] = [], topics: [FlaggedTopicStamp] = []) {
        self.newPrivateMessages = newPrivateMessages
        self.newThreads = newThreads
        self.topics = topics
    }

    /// Whether there is nothing to notify.
    public var isEmpty: Bool {
        newPrivateMessages == 0 && newThreads.isEmpty && topics.isEmpty
    }
}
