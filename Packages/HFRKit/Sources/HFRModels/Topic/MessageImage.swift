import Foundation

/// An image of a message body or signature; only http(s) URLs reach this type.
public struct MessageImage: Sendable, Hashable, Codable {
    /// Image URL (after the `reho.st` host fix).
    public var url: URL
    /// Target of the surrounding link, when the image is wrapped in one.
    public var linkURL: URL?
    /// The `alt` text.
    public var altText: String
    /// True when the image sits in the signature.
    public var isInSignature: Bool

    /// Creates an image.
    public init(url: URL, linkURL: URL? = nil, altText: String = "", isInSignature: Bool = false) {
        self.url = url
        self.linkURL = linkURL
        self.altText = altText
        self.isInSignature = isInSignature
    }
}
