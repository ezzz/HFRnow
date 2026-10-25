import Foundation

/// The data `addAlerte.php` needs to report a message; encoding it (fixed field order) is a network concern.
public struct AQNewReport: Sendable, Hashable, Codable {
    /// Existing AQ to add the message to; nil creates a new AQ (`alerte_qualitay_id=-1`).
    public var existingAlertID: Int?
    /// Title of the AQ (`nom`).
    public var title: String
    /// Topic number (`topic_id`).
    public var topicID: Int
    /// Topic title (`topic_titre`).
    public var topicTitle: String
    /// Reporter pseudo (`pseudo`); sent to a third party, unauthenticated.
    public var pseudo: String
    /// Reported message number (`post_id`).
    public var postID: Int
    /// Permalink of the reported message (`post_url`).
    public var postURL: URL
    /// Free comment (`commentaire`).
    public var comment: String

    /// Creates a report.
    public init(
        existingAlertID: Int? = nil,
        title: String,
        topicID: Int,
        topicTitle: String,
        pseudo: String,
        postID: Int,
        postURL: URL,
        comment: String
    ) {
        self.existingAlertID = existingAlertID
        self.title = title
        self.topicID = topicID
        self.topicTitle = topicTitle
        self.pseudo = pseudo
        self.postID = postID
        self.postURL = postURL
        self.comment = comment
    }
}
