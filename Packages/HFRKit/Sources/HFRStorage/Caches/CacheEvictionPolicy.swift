import Foundation

/// When files leave a cache: too old, or too much data (oldest files go first).
public struct CacheEvictionPolicy: Sendable, Hashable {
    /// Files last written longer ago than this are removed; nil keeps files whatever their age.
    public var maximumAge: TimeInterval?
    /// Once age rules are applied, the oldest files are removed until at most this many bytes remain; nil means no bound.
    public var maximumTotalBytes: Int?
    /// Removes every regular file, whatever its date or size (including empty and future-dated files).
    public var removesEverything: Bool

    /// Creates a policy.
    public init(maximumAge: TimeInterval? = nil, maximumTotalBytes: Int? = nil, removesEverything: Bool = false) {
        self.maximumAge = maximumAge
        self.maximumTotalBytes = maximumTotalBytes
        self.removesEverything = removesEverything
    }

    /// Removes every file whatever its date or size: used to clear an area.
    public static let everything = CacheEvictionPolicy(removesEverything: true)
    /// Avatars: 25 days like the legacy launch pruning (`HFRplusAppDelegate.m:539-560`), and a 50 MB bound that legacy lacked.
    public static let avatars = CacheEvictionPolicy(maximumAge: 25 * 86_400, maximumTotalBytes: 50_000_000)
    /// Topic pages: one day (legacy never removed them, audit E §7.10) and a 20 MB bound.
    public static let topicPages = CacheEvictionPolicy(maximumAge: 86_400, maximumTotalBytes: 20_000_000)
}
