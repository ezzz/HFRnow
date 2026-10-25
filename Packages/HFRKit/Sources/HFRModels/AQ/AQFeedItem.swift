import Foundation

/// One entry of the AQ ("Alerte Qualitay") RSS feed.
public struct AQFeedItem: Sendable, Hashable, Identifiable, Codable {
    /// Stable identity: link, title and publication instant (the feed has no guid we rely on).
    public var id: String { "\(link.absoluteString)|\(title)|\(publishedAt?.timeIntervalSince1970 ?? 0)" }
    /// Title of the topic the alert was raised in.
    public var topicTitle: String
    /// Title of the AQ itself.
    public var title: String
    /// Comment left by the initiator.
    public var comment: String
    /// Pseudo of the initiator.
    public var initiator: String
    /// Publication date; nil when the feed date could not be read.
    public var publishedAt: Date?
    /// Link to the reported message; its `cat` parameter lets callers filter categories.
    public var link: URL

    /// Creates a feed item.
    public init(topicTitle: String, title: String, comment: String, initiator: String, publishedAt: Date?, link: URL) {
        self.topicTitle = topicTitle
        self.title = title
        self.comment = comment
        self.initiator = initiator
        self.publishedAt = publishedAt
        self.link = link
    }
}
