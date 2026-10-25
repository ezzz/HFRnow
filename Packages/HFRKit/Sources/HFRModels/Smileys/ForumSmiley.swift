import Foundation

/// A smiley as the forum lists it: personal favourites of a form, or a search result.
public struct ForumSmiley: Sendable, Hashable, Codable {
    /// Smiley code from the `alt` attribute, e.g. `[:ezzz]` (kept exactly as served).
    public var code: String
    /// Image URL, used as given (paths may contain spaces and sub-folders).
    public var url: URL

    /// Creates a smiley.
    public init(code: String, url: URL) {
        self.code = code
        self.url = url
    }
}
