import ImageIO
import UIKit

// Port of HFRswift/Swift/AnswerView.swift (SmileyThumbnailView.Coordinator image loading) @ 2440d79. Differences: policy-C
// cookie-less fetch instead of URLSession.shared, no bundled GIFs, ImageIO only (GAP-087).
/// Loads and caches smiley images for the picker (LOT-104; absorbs the Phase 4 item "image/GIF decoding (E-8)").
///
/// Images come through `ReaderImageFetcher`, i.e. the cookie-less client and policy C: no forum cookie leaves the app
/// and a host the policy does not allow is never contacted (`allowsThirdParty: false`: smileys live on the forum image
/// host). Legacy bundled the GIFs and fell back to `URLSession.shared` for favourites (`AnswerView.swift:1651-1760`).
/// An animated GIF becomes a `UIImage` animation, decoded with ImageIO as legacy's own fallback did (no SDWebImage).
struct SmileyImageLoader: Sendable {
    /// `NSCache` is thread-safe; the box only states it for the compiler.
    private final class Cache: @unchecked Sendable {
        let storage: NSCache<NSURL, UIImage> = {
            let cache = NSCache<NSURL, UIImage>()
            cache.countLimit = 400
            return cache
        }()
    }

    private static let shared = Cache()

    let fetcher: ReaderImageFetcher

    /// A loader over `fetcher`, the cookie-less one by default.
    init(fetcher: ReaderImageFetcher = ReaderImageFetcher()) {
        self.fetcher = fetcher
    }

    /// The image already decoded for `url`, if any (no work, no request).
    static func cached(_ url: URL) -> UIImage? {
        shared.storage.object(forKey: url as NSURL)
    }

    /// The image at `url`: from the cache, else downloaded and decoded; nil when it cannot be had.
    func image(at url: URL) async -> UIImage? {
        if let cached = Self.cached(url) { return cached }
        guard let (data, _) = try? await fetcher.image(at: url, allowsThirdParty: false),
              !Task.isCancelled, let image = Self.decode(data) else { return nil }
        Self.shared.storage.setObject(image, forKey: url as NSURL)
        return image
    }

    /// Decodes `data`, animating multi-frame GIFs (legacy `decodeGIFImage`, `AnswerView.swift:1738-1760`).
    static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return UIImage(data: data) }
        let count = CGImageSourceGetCount(source)
        guard count > 1 else { return UIImage(data: data) }
        var frames: [UIImage] = []
        var duration = 0.0
        for index in 0..<count {
            guard let frame = CGImageSourceCreateImageAtIndex(source, index, nil) else { continue }
            duration += frameDuration(at: index, in: source)
            frames.append(UIImage(cgImage: frame, scale: 1, orientation: .up))
        }
        guard !frames.isEmpty else { return UIImage(data: data) }
        if duration <= 0 { duration = Double(frames.count) * 0.1 }
        return UIImage.animatedImage(with: frames, duration: duration)
    }

    /// A frame's delay in seconds; 0.1 s when missing or under 0.011 s, as browsers and legacy do.
    static func frameDuration(at index: Int, in source: CGImageSource) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else { return 0.1 }
        let delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
        return delay < 0.011 ? 0.1 : delay
    }
}
