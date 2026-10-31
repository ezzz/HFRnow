import Foundation
import HFRModels

/// One topic page saved for reading without network: the page as HFR served it to a visitor, read back by the parser.
public struct OfflinePage: Sendable, Equatable {
    /// The topic (a forum topic: private conversations are never saved).
    public let topic: TopicID
    /// The page number, 1 or more.
    public let page: Int
    /// The topic title shown in the offline list, as the caller read it.
    public let title: String
    /// The page's HTML as fetched without cookies (no `hash_check` token in it).
    public let html: String
    /// When the page was saved.
    public let savedAt: Date

    /// Creates a page.
    public init(topic: TopicID, page: Int, title: String, html: String, savedAt: Date) {
        self.topic = topic
        self.page = page
        self.title = title
        self.html = html
        self.savedAt = savedAt
    }
}
