import Foundation
import HFRModels

/// A topic with pages saved for reading without network, as the offline list shows it.
public struct OfflineTopic: Sendable, Equatable {
    /// The topic.
    public let topic: TopicID
    /// The title saved with its highest readable page; empty when no page of the topic can be read.
    public let title: String
    /// The saved page numbers, ascending.
    public let pages: [Int]
    /// When the topic's most recent page file was written.
    public let lastSavedAt: Date
}
