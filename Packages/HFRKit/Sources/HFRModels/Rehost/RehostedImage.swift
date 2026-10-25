import Foundation

/// An image uploaded to the image host (Chevereto), with the renditions the host returned.
public struct RehostedImage: Sendable, Hashable, Identifiable, Codable {
    /// Stable identity: full URL plus upload instant (the same image may be uploaded twice).
    public var id: String { "\(fullURL.absoluteString)|\(uploadedAt.timeIntervalSince1970)" }
    /// URL of the full image.
    public var fullURL: URL
    /// URL of the medium rendition, if any.
    public var mediumURL: URL?
    /// URL of the thumbnail, if any.
    public var miniURL: URL?
    /// Pixel width of the full image.
    public var width: Int?
    /// Pixel height of the full image.
    public var height: Int?
    /// When the upload finished.
    public var uploadedAt: Date

    /// Creates an uploaded image description.
    public init(
        fullURL: URL,
        mediumURL: URL? = nil,
        miniURL: URL? = nil,
        width: Int? = nil,
        height: Int? = nil,
        uploadedAt: Date
    ) {
        self.fullURL = fullURL
        self.mediumURL = mediumURL
        self.miniURL = miniURL
        self.width = width
        self.height = height
        self.uploadedAt = uploadedAt
    }

    /// Variants that exist, `full` always included.
    public var availableVariants: [RehostImageVariant] {
        var variants: [RehostImageVariant] = [.full]
        if mediumURL != nil { variants.append(.medium) }
        if miniURL != nil { variants.append(.mini) }
        return variants
    }

    /// URL of a variant; a missing rendition falls back to the next larger one (mini, then medium, then full).
    public func url(for variant: RehostImageVariant) -> URL {
        switch variant {
        case .full: fullURL
        case .medium: mediumURL ?? fullURL
        case .mini: miniURL ?? mediumURL ?? fullURL
        }
    }

    /// Text to insert in a post for a variant; the BBCode forms end with a newline, the bare URL does not.
    public func snippet(variant: RehostImageVariant, mode: RehostBBCodeMode) -> String {
        let target = url(for: variant).absoluteString
        switch mode {
        case .linkOnly: return target
        case .imageNoLink: return "[img]\(target)[/img]\n"
        case .imageWithLink: return "[url=\(fullURL.absoluteString)][img]\(target)[/img][/url]\n"
        }
    }
}
