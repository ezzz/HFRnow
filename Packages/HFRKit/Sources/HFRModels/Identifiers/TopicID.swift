/// Identifies a topic: HFR numbers topics inside their category, so the pair is the key (`cat` + `post` in URLs).
public struct TopicID: Sendable, Hashable, Codable {
    /// Category the topic lives in.
    public var category: CategoryID
    /// Topic number inside the category (the `post` query parameter).
    public var topic: Int

    /// Creates a topic identifier.
    public init(category: CategoryID, topic: Int) {
        self.category = category
        self.topic = topic
    }
}
