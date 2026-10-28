import Foundation
/// What SwiftHFR knows about one image host: a row of `ImageHostTable`, kept as data so a capture can change it.
///
/// A rule never carries an API key: only the upload (`RehostClient`) needs one, and it is configuration (ADR 0007).
public struct ImageHostRule: Sendable, Equatable {
    /// How a thumbnail URL of this host maps to the full image.
    public enum ThumbnailRewrite: Sendable, Equatable {
        /// The path starts with `from` (whole components, for example `/thumb/`): replace that prefix with `to`.
        case pathPrefix(from: String, to: String)
        /// Under `pathPrefix`, the file name carries `marker` (for example `.th.`): remove it.
        case fileNameMarker(pathPrefix: String, marker: String)
    }

    /// Lower-case host name without trailing dot, for example `reho.st`.
    public var host: String
    /// Whether subdomains match too (`i.reho.st`), at a label boundary.
    public var includesSubdomains: Bool
    /// `Referer` the host needs to serve its images; `nil` means none is sent (HFR-PROTOCOL §7, E26).
    public var referer: String?
    /// True when every captured reference to this host is `http://`: the app must decide how to load it
    /// (LOT-083, D-071-1 point 4). Whether `https` works is not measured, so the table never rewrites the scheme.
    public var observedHTTPOnly: Bool
    /// True when image URLs of this host have no file extension, so the extension cannot tell an image from a page.
    public var servesExtensionlessImages: Bool
    /// How to get from a thumbnail URL to the full image, if the host has thumbnails.
    public var thumbnailRewrite: ThumbnailRewrite?

    /// Creates a rule; every field but the host is optional data.
    public init(
        host: String,
        includesSubdomains: Bool = true,
        referer: String? = nil,
        observedHTTPOnly: Bool = false,
        servesExtensionlessImages: Bool = false,
        thumbnailRewrite: ThumbnailRewrite? = nil
    ) {
        self.host = host
        self.includesSubdomains = includesSubdomains
        self.referer = referer
        self.observedHTTPOnly = observedHTTPOnly
        self.servesExtensionlessImages = servesExtensionlessImages
        self.thumbnailRewrite = thumbnailRewrite
    }

    /// True when `candidate` (already lower-cased, no trailing dot) is this host or, if allowed, one of its subdomains.
    func matches(_ candidate: String) -> Bool {
        candidate == host || (includesSubdomains && candidate.hasSuffix("." + host))
    }
}
