import HFRModels

/// One topic's position in the store.
public struct ReadingPositionRecord: Sendable, Hashable, Codable {
    /// The topic.
    public var topic: TopicID
    /// Where the account stopped.
    public var position: ReadingPosition

    /// Creates a record.
    public init(topic: TopicID, position: ReadingPosition) {
        self.topic = topic
        self.position = position
    }
}
