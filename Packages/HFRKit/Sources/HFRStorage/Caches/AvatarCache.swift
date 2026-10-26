import Foundation

/// A cached avatar file.
public struct AvatarCacheEntry: Sendable, Equatable {
    /// The file; image decoding is the caller's business.
    public let fileURL: URL
    /// When the file was written.
    public let storedAt: Date
    /// Whether it is younger than `AvatarCache.freshnessInterval`.
    public let isFresh: Bool
}

/// Avatar files keyed by pseudo.
///
/// Rules from the legacy parser (`ParseMessagesOperation.m:423-467`, audit C17): the key ignores case; a file older than
/// 24 hours is *stale* and should be downloaded again; a failed download must not remove a valid stale file. The
/// last rule holds by construction: nothing here deletes on a miss, and `store` writes atomically.
///
/// There is no memory state, so this is a plain value type; the file system is the shared state.
public struct AvatarCache: Sendable {
    /// After 24 hours an avatar should be fetched again.
    public static let freshnessInterval: TimeInterval = 24 * 60 * 60
    /// Longest accepted key, in UTF-8 bytes. The file name is the hex of the key, which must stay under 255 characters.
    public static let maximumKeyBytes = 100

    private let cache: CacheDirectory

    /// Creates an avatar cache in the `avatars` area of `cache`.
    public init(cache: CacheDirectory) {
        self.cache = cache
    }

    /// The cached file of a pseudo, fresh or stale, or nil when there is none. The caller decides whether to refresh.
    public func entry(forPseudo pseudo: String, now: Date = .now) throws -> AvatarCacheEntry? {
        let url = try fileURL(forPseudo: pseudo)
        guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .contentModificationDateKey]),
              values.isRegularFile == true else { return nil }
        let stored = values.contentModificationDate ?? .distantPast
        return AvatarCacheEntry(fileURL: url, storedAt: stored, isFresh: now.timeIntervalSince(stored) <= Self.freshnessInterval)
    }

    /// Writes the avatar bytes atomically, replacing any previous file. Empty data is refused so that a bad download
    /// can never replace a good file.
    @discardableResult
    public func store(_ data: Data, forPseudo pseudo: String) throws -> URL {
        guard !data.isEmpty else { throw CacheError.emptyData }
        let directory = try cache.prepare(.avatars)
        let url = directory.appending(path: try Self.fileName(forPseudo: pseudo), directoryHint: .notDirectory)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Removes the avatar of a pseudo (for example when the user asks to reload it). Returns false when there was none.
    @discardableResult
    public func remove(forPseudo pseudo: String) throws -> Bool {
        let url = try fileURL(forPseudo: pseudo)
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return false }
        try FileManager.default.removeItem(at: url)
        return true
    }

    /// The file name for a pseudo: lower-cased, zero-width spaces removed, then hex of the UTF-8 bytes. The encoding is
    /// reversible, so two pseudos never share a file (a hash would let someone pick a colliding pseudo).
    static func fileName(forPseudo pseudo: String) throws -> String {
        let normalized = pseudo.filter { $0 != "\u{200B}" }.lowercased()
        guard !normalized.isEmpty else { throw CacheError.emptyKey }
        guard normalized.utf8.count <= maximumKeyBytes else { throw CacheError.keyTooLong }
        let digits = Array("0123456789abcdef")
        return String(normalized.utf8.flatMap { [digits[Int($0 >> 4)], digits[Int($0 & 0x0F)]] })
    }

    private func fileURL(forPseudo pseudo: String) throws -> URL {
        try cache.safeURL(for: .avatars).appending(path: try Self.fileName(forPseudo: pseudo), directoryHint: .notDirectory)
    }
}
