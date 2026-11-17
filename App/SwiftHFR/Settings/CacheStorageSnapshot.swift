import Foundation
import HFRStorage

// Port of HFRswift/Swift/HTMLPageCacheManager.swift (AppCacheStorageSnapshot, storageSnapshot, cachedHTMLFiles,
// directoryAllocatedSize) @ 87fe0d1c. Differences: "Pages HTML" counts the `topic-*.htm` files of LOT-066's `pages` area
// (`Caches/cache/pages`), not the ones directly under `Caches/cache`; "fichier" is singular below two (GAP-152, LOT-179 spec).
/// What Réglages > Maintenance shows about the app's caches: all of `Library/Caches`, and the topic pages among it.
struct CacheStorageSnapshot: Equatable, Sendable {
    /// Allocated size of every visible regular file under `Caches`, recursively ("Caches de l'app").
    let totalBytes: Int64
    /// Allocated size of the cached topic pages ("Pages HTML").
    let htmlBytes: Int64
    /// Number of cached topic pages.
    let htmlFileCount: Int

    /// The figures of `Library/Caches` and of the `pages` area of the standard cache folder.
    static func measureStandard() -> CacheStorageSnapshot {
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL.temporaryDirectory
        let cache = CacheDirectory(root: caches.appending(path: "cache", directoryHint: .isDirectory))
        // An area that is a link or leaves the cache is not read (it is not purged either): zero pages.
        return measure(cachesDirectory: caches, pagesDirectory: try? cache.safeURL(for: .topicPages))
    }

    /// Measures `cachesDirectory` (hidden files and folders skipped, as legacy) and the topic pages directly in `pagesDirectory`.
    /// A missing or unreadable folder counts as empty.
    static func measure(cachesDirectory: URL, pagesDirectory: URL?) -> CacheStorageSnapshot {
        let pages = pagesDirectory.map(topicPageSizes(in:)) ?? []
        return CacheStorageSnapshot(
            totalBytes: allocatedSize(under: cachesDirectory),
            htmlBytes: pages.reduce(0, +),
            htmlFileCount: pages.count
        )
    }

    private static let sizeKeys: [URLResourceKey] = [
        .isRegularFileKey, .totalFileAllocatedSizeKey, .fileAllocatedSizeKey, .fileSizeKey
    ]

    private static func allocatedSize(of url: URL) -> Int64? {
        guard let values = try? url.resourceValues(forKeys: Set(sizeKeys)), values.isRegularFile == true else { return nil }
        return Int64(values.totalFileAllocatedSize ?? values.fileAllocatedSize ?? values.fileSize ?? 0)
    }

    private static func allocatedSize(under directory: URL) -> Int64 {
        guard let walker = FileManager.default.enumerator(
            at: directory, includingPropertiesForKeys: sizeKeys, options: [.skipsHiddenFiles]
        ) else { return 0 }
        var total: Int64 = 0
        for case let url as URL in walker { total += allocatedSize(of: url) ?? 0 }
        return total
    }

    private static func topicPageSizes(in directory: URL) -> [Int64] {
        let urls = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: sizeKeys, options: [.skipsHiddenFiles]
        )) ?? []
        return urls.compactMap { url in
            guard url.lastPathComponent.hasPrefix("topic-"), url.pathExtension.lowercased() == "htm" else { return nil }
            return allocatedSize(of: url)
        }
    }
}

/// The texts of the cache rows, as pure functions so they can be tested.
enum CacheStorageText {
    /// A size as Settings shows it (`.byteCount(style: .file)`, legacy `formattedStorageSize`).
    static func size(_ bytes: Int64) -> String {
        bytes.formatted(.byteCount(style: .file))
    }

    /// "12 fichiers"; "fichier" is singular for 0 and 1 (legacy wrote "1 fichiers").
    static func fileCount(_ count: Int) -> String {
        "\(count) \(count < 2 ? "fichier" : "fichiers")"
    }

    /// The footer: SwiftHFR's own rule for topic pages (`CacheEvictionPolicy.topicPages`), worded as legacy
    /// ("Les pages HTML de plus de 7 jours sont supprimées automatiquement. Leur cache est limité à 50 Mo.").
    static func purgeRule(for policy: CacheEvictionPolicy = .topicPages) -> String {
        var sentences: [String] = []
        if let age = policy.maximumAge {
            let days = max(1, Int((age / 86_400).rounded()))
            let span = days == 1 ? "d’un jour" : "de \(days) jours"
            sentences.append("Les pages HTML de plus \(span) sont supprimées automatiquement.")
        }
        if let bytes = policy.maximumTotalBytes {
            // Legacy counts a megabyte as 1 000 000 bytes (`maximumSize`, `HTMLPageCacheManager.swift:22`).
            sentences.append("Leur cache est limité à \(bytes / 1_000_000) Mo.")
        }
        return sentences.joined(separator: " ")
    }
}
