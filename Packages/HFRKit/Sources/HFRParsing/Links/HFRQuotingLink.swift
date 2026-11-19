import Foundation
import HFRModels

/// The « Message cité N fois » link of a message (`quote_only=1`, #1039; the `div.edited` link of `R353a`), read into the values
/// the quote view's request is rebuilt from (`HFREndpoint.quotingMessages`): the account session never replays the link as
/// written (LESSONS 37, 43).
public struct HFRQuotingLink: Sendable, Hashable {
    /// The topic the cited message belongs to.
    public var topic: TopicID
    /// The link's `subcat=`; nil when empty or absent.
    public var subcategory: Int?
    /// The cited message.
    public var numreponse: Int

    /// Creates a quoting link.
    public init(topic: TopicID, subcategory: Int?, numreponse: Int) {
        self.topic = topic
        self.subcategory = subcategory
        self.numreponse = numreponse
    }

    /// Nil unless `url` is a `forum2.php` link of `forum.hardware.fr` (exact host, no port or user info) with `quote_only=1`, the
    /// default forum configuration, a public category, a topic and a message number; any other value is refused, never guessed.
    public init?(url: URL) {
        guard let target = HFRLinkRoute.Target(url), target.path == "/forum2.php", target.isQuoteOnlyView else { return nil }
        do {
            try target.requireForumConfig()
            guard let post = try target.positive("post"), let message = try target.numreponse() else { return nil }
            // Only a public topic's quote view was captured (`R126a`): a private thread's shape is not guessed.
            let category = try target.category()
            guard category != .privateMessages else { return nil }
            self.init(topic: TopicID(category: category, topic: post), subcategory: try target.positive("subcat"), numreponse: message)
        } catch {
            return nil
        }
    }
}
