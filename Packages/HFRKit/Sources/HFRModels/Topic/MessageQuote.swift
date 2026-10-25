/// A quote block found in a message.
public struct MessageQuote: Sendable, Hashable, Codable {
    /// Quoted author; nil for anonymous quotes.
    public var author: String?
    /// Nesting depth, 1 for a quote directly in the message (the initializer raises values below 1 to 1).
    public var depth: Int
    /// Number of the cited message, read from the `#t<id>` fragment of the header link.
    public var citedNumreponse: Int?

    /// Creates a quote description; `depth` is raised to at least 1.
    public init(author: String? = nil, depth: Int = 1, citedNumreponse: Int? = nil) {
        self.author = author
        self.depth = max(1, depth)
        self.citedNumreponse = citedNumreponse
    }
}
