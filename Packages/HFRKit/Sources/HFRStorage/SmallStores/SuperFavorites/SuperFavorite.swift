import Foundation
import HFRModels

/// One super-favourite topic of an account.
public struct SuperFavorite: Sendable, Hashable, Codable {
    /// The topic: category and number, since a topic number alone is only unique inside its category.
    public var topic: TopicID
    /// When the topic was marked; the iCloud list of LOT-172 carries it (`{id, addedAt}`, ADR 0013 §3).
    public var addedAt: Date

    /// Creates a super-favourite.
    public init(topic: TopicID, addedAt: Date) {
        self.topic = topic
        self.addedAt = addedAt
    }
}
