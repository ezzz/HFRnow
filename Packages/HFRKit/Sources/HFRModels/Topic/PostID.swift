/// Globally unique key of a message: HFR numbers messages (`numreponse`) per category, so the triple is the key.
public struct PostID: Sendable, Hashable, Codable {
    /// Topic holding the message.
    public var topic: TopicID
    /// Message number inside the category (the `t<number>` anchor).
    public var numreponse: Int

    /// Creates a message key.
    public init(topic: TopicID, numreponse: Int) {
        self.topic = topic
        self.numreponse = numreponse
    }
}
