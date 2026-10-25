import Foundation

/// The most recent message of a topic as summarised in a list row.
public struct LastPost: Sendable, Hashable, Codable {
    /// Pseudo of the author.
    public var author: String
    /// Path of the message, relative to the forum base URL.
    public var path: String
    /// Posting date (HFR serves it in Europe/Paris time); nil when the cell shows a label that cannot be dated.
    public var date: Date?

    /// Creates a last post summary.
    public init(author: String, path: String, date: Date? = nil) {
        self.author = author
        self.path = path
        self.date = date
    }
}
