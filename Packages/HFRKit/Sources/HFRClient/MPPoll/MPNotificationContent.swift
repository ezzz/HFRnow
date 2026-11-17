/// One local notification of the background MP check (LOT-140): what it says and where a tap leads.
public struct MPNotificationContent: Sendable, Hashable {
    /// The request identifier: a later notification with the same one replaces it instead of stacking.
    public var identifier: String
    /// Groups the notifications of one conversation in Notification Center.
    public var threadIdentifier: String
    /// The first line: the interlocutor of a one-to-one conversation, the title of a group one.
    public var title: String
    /// The second line: the conversation's title for a one-to-one conversation, empty for a group one.
    public var body: String
    /// The conversation's topic number a tap opens; nil for a summary, which opens the list.
    public var topic: Int?

    /// Creates a notification content.
    public init(identifier: String, threadIdentifier: String, title: String, body: String, topic: Int?) {
        self.identifier = identifier
        self.threadIdentifier = threadIdentifier
        self.title = title
        self.body = body
        self.topic = topic
    }
}
