/// The arguments of the site's `quoter('hardwarefr', cat, post, numreponse)` link, used for multi-quote.
public struct QuoteSelectionToken: Sendable, Hashable, Codable {
    /// Forum config name, `hardwarefr`.
    public var forum: String
    /// Topic the message belongs to.
    public var topic: TopicID
    /// Message number inside the category.
    public var numreponse: Int

    /// Creates a token.
    public init(forum: String, topic: TopicID, numreponse: Int) {
        self.forum = forum
        self.topic = topic
        self.numreponse = numreponse
    }
}
