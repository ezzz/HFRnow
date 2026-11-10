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

    let cache: CacheDirectory

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

    /// Largest legacy avatar file accepted, in bytes (the download cap of `AnonymousAvatarLoader`).
    public static let legacyMaximumBytes = 256 * 1024

    /// The cached file of a pseudo; when there is none, the one the legacy app cached under `MD5(lowercased pseudo)` in the
    /// same folder (`MPListView.swift:911-917` @ `87fe0d1c`), adopted under the SwiftHFR name. The legacy file is only read
    /// (never changed or removed). It is taken only if it is a regular file, not a link, within `legacyMaximumBytes`, and
    /// `accepting` approves its bytes (the app checks that they decode as an image); the copy keeps the legacy file's date so
    /// an old avatar is still refreshed from the pages. Any failure is no entry.
    public func entryAdoptingLegacy(forPseudo pseudo: String, accepting: (Data) -> Bool, now: Date = .now) throws -> AvatarCacheEntry? {
        if let entry = try entry(forPseudo: pseudo, now: now) { return entry }
        let directory = try cache.safeURL(for: .avatars)
        for name in LegacyAvatarName.candidates(forPseudo: pseudo) {
            let url = directory.appending(path: name, directoryHint: .notDirectory)
            guard let (data, date) = Self.readLegacyFile(url), accepting(data) else { continue }
            let stored = try store(data, forPseudo: pseudo)
            // Best effort: a failure only makes the avatar look fresh for a day.
            try? FileManager.default.setAttributes([.modificationDate: date], ofItemAtPath: stored.path(percentEncoded: false))
            return try entry(forPseudo: pseudo, now: now)
        }
        return nil
    }

    /// `attributesOfItem` does not follow a final symbolic link, so a link reports `.typeSymbolicLink` and is refused.
    private static func readLegacyFile(_ url: URL) -> (Data, Date)? {
        let path = url.path(percentEncoded: false)
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: path),
              attributes[.type] as? FileAttributeType == .typeRegular,
              let size = attributes[.size] as? NSNumber, size.intValue > 0, size.intValue <= legacyMaximumBytes,
              let data = try? Data(contentsOf: url), !data.isEmpty, data.count <= legacyMaximumBytes else { return nil }
        return (data, (attributes[.modificationDate] as? Date) ?? .distantPast)
    }
}
