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
            cache.totalCostLimit = maximumCacheBytes
            return cache
        }()
    }

    /// Decoded memory the cache may hold; each entry costs its frames' pixels, not one count.
    private static let maximumCacheBytes = 48 * 1024 * 1024
    /// Most decoded pixels (all frames) one animation may take: a larger GIF is shown as its first frame only, so a
    /// download within the fetcher's size cap cannot expand into hundreds of MB of frames.
    static let maximumAnimationPixels = 4_000_000

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
        Self.shared.storage.setObject(image, forKey: url as NSURL, cost: cost(of: image))
        return image
    }

    /// Decodes `data`, animating multi-frame GIFs (legacy `decodeGIFImage`, `AnswerView.swift:1738-1760`).
    static func decode(_ data: Data) -> UIImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return UIImage(data: data) }
        let count = CGImageSourceGetCount(source)
        guard count > 1, pixelCount(of: source) * count <= maximumAnimationPixels else { return UIImage(data: data) }
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

    /// Pixels of the first frame (0 when unreadable, which keeps the animation out: callers compare a product).
    private static func pixelCount(of source: CGImageSource) -> Int {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = properties[kCGImagePropertyPixelWidth] as? Int,
              let height = properties[kCGImagePropertyPixelHeight] as? Int else { return Int.max / 4096 }
        return width * height
    }

    /// Bytes an image holds once decoded (4 per pixel, every frame).
    private static func cost(of image: UIImage) -> Int {
        let frames = max(image.images?.count ?? 1, 1)
        return Int(image.size.width * image.scale * image.size.height * image.scale) * 4 * frames
    }

    /// A frame's delay in seconds; 0.1 s when missing or under 0.011 s, as browsers and legacy do.
    static func frameDuration(at index: Int, in source: CGImageSource) -> Double {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [CFString: Any],
              let gif = properties[kCGImagePropertyGIFDictionary] as? [CFString: Any] else { return 0.1 }
        let delay = (gif[kCGImagePropertyGIFUnclampedDelayTime] as? Double) ?? (gif[kCGImagePropertyGIFDelayTime] as? Double) ?? 0.1
        return delay < 0.011 ? 0.1 : delay
    }
}
