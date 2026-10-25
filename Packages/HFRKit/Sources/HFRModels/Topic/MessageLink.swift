import Foundation

/// A link of a message body or signature; only http(s) URLs reach this type (other schemes become plain text).
public struct MessageLink: Sendable, Hashable, Codable {
    /// Absolute link target.
    public var url: URL
    /// Visible link text.
    public var text: String
    /// True when the link sits in the signature.
    public var isInSignature: Bool

    /// Creates a link.
    public init(url: URL, text: String, isInSignature: Bool = false) {
        self.url = url
        self.text = text
        self.isInSignature = isInSignature
    }
}
