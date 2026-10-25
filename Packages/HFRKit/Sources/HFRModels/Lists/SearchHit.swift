/// The extra data a search result row carries about the matching message.
public struct SearchHit: Sendable, Hashable, Codable {
    /// Path of the matching message, relative to the forum base URL.
    public var postPath: String
    /// Text excerpt HFR shows under the title.
    public var snippet: String

    /// Creates a search hit.
    public init(postPath: String, snippet: String) {
        self.postPath = postPath
        self.snippet = snippet
    }
}
