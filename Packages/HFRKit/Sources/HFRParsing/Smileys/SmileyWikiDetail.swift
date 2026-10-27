import Foundation

/// The wiki entry of one personal smiley (`/wikismilies.php?config=hfr.inc&detail=<code>`, HFR-PROTOCOL R54).
public struct SmileyWikiDetail: Sendable, Equatable {
    /// Smiley code as served, e.g. `[:name]`.
    public var code: String
    /// Smiley image; nil when the page has none or it is not an `https`/`http` URL.
    public var imageURL: URL?
    /// Keywords the community attached to the smiley, in the order served.
    public var keywords: [String]

    /// Creates a wiki entry.
    public init(code: String, imageURL: URL?, keywords: [String]) {
        self.code = code
        self.imageURL = imageURL
        self.keywords = keywords
    }
}
