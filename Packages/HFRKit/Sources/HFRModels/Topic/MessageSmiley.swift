import Foundation

/// A smiley of a message body.
public struct MessageSmiley: Sendable, Hashable, Codable {
    /// Where the smiley comes from.
    public enum Kind: String, Sendable, Codable {
        /// Standard forum smiley.
        case standard
        /// Personal smiley (`images/perso/`).
        case custom
    }

    /// Smiley code, e.g. `:)` (without the surrounding `[` `]` of the `alt` attribute).
    public var code: String
    /// Image URL.
    public var url: URL
    /// Standard or personal smiley.
    public var kind: Kind

    /// Creates a smiley.
    public init(code: String, url: URL, kind: Kind) {
        self.code = code
        self.url = url
        self.kind = kind
    }
}
