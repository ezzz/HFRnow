import Foundation
import HFRNetwork

// Port of HFRswift/Swift/MessagesView.swift (`normalizeImageViewerURL`, `:3298-3312`; `PhotoViewerDestination`, `:2567`) @ 2440d79.
// Differences: GAP-057 / FEAT-014: the viewer swipes between the images of the page (legacy opened one URL), and what may be
// requested is decided here by policy C, never by the page.

/// One image of the viewer: what the page showed and what the viewer asks for.
struct GalleryImage: Equatable, Sendable, Identifiable {
    /// The `src` the page showed (a thumbnail on rehost hosts); the fallback when the full-size URL fails.
    let shown: URL
    /// The full-size URL from the host table (LOT-056), equal to `shown` for a host without a rewrite rule.
    let full: URL
    /// Whether a redirect of this image may reach a third party (it is one, or the setting loads third parties anyway).
    let allowsThirdParty: Bool

    var id: URL { shown }
}

/// Which images of a document the viewer may show, from the list the page reported (LOT-109).
enum ImageGallery {
    /// Most images one viewer holds.
    static let maximumImages = 500

    /// The viewable images among `sources` and the position of `selected` among them.
    ///
    /// The page's list is a claim, not an authority: an entry is kept only when the policy would let the reader load it
    /// by itself now: a forum image, or a third-party image the user already consented to (or that the setting loads
    /// anyway). A neighbour the user never allowed (a placeholder) never enters the gallery, so a swipe cannot fetch it.
    /// Nil when the tapped image itself is not allowed.
    static func build(
        sources: [String], selected: Int, consented: Set<String>, autoLoadsThirdParty: Bool,
        hosts: ImageHostTable = .standard
    ) -> (images: [GalleryImage], index: Int)? {
        guard sources.indices.contains(selected) else { return nil }
        // A window of at most `maximumImages` around the tapped picture, so a picture late on a huge page still opens.
        let lower = max(0, min(selected - maximumImages / 2, sources.count - maximumImages))
        var images: [GalleryImage] = []
        var index: Int?
        for position in lower..<min(sources.count, lower + maximumImages) {
            let text = sources[position]
            let isSelected = position == selected
            guard let url = URL(string: text) else { continue }
            let origin = ImagePolicy.classify(url)
            switch origin {
            case .blocked: continue
            case .thirdParty where !(autoLoadsThirdParty || consented.contains(text)): continue
            case .forum, .thirdParty: break
            }
            let full = hosts.fullSizeURL(for: url)
            // The consent the user gave covers the picture's own host: a rewrite that changes the host or the origin is ignored.
            let usable = ImagePolicy.classify(full) == origin && full.host()?.lowercased() == url.host()?.lowercased() ? full : url
            if isSelected { index = images.count }
            images.append(GalleryImage(shown: url, full: usable, allowsThirdParty: origin == .thirdParty || autoLoadsThirdParty))
        }
        guard let index else { return nil }
        return (images, index)
    }
}
