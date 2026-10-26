import Foundation

/// The app's cache folder and its areas. Everything here can be deleted by the system or by the user at any time.
///
/// The default root is `Library/Caches/cache`, the same folder the legacy app used, so avatars cached by the old
/// version are simply pruned by age. The offline-reading feature is not part of it (LOT-068).
public struct CacheDirectory: Sendable {
    /// The folder holding all areas.
    public let root: URL

    /// Creates a cache over `root` (tests pass a temporary directory).
    public init(root: URL) {
        self.root = root
    }

    /// `Library/Caches/cache` of the app.
    public static var standard: CacheDirectory {
        // `URL.cachesDirectory` is Apple-only; the FileManager lookup also works on Linux.
        let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first ?? URL.temporaryDirectory
        return CacheDirectory(root: caches.appending(path: "cache", directoryHint: .isDirectory))
    }

    /// The folder of an area, without creating it.
    public func url(for area: CacheArea) -> URL {
        root.appending(path: area.rawValue, directoryHint: .isDirectory)
    }

    /// The folder of an area after checking that neither the root nor the area is a symbolic link and that the area
    /// really lives inside the root. Components that do not exist yet are fine; throws `CacheError.unsafeFolder` otherwise.
    /// Every read, write or removal in an area goes through this check, so a link can never redirect it.
    public func safeURL(for area: CacheArea) throws -> URL {
        let area = url(for: area)
        for folder in [root, area] where Self.isSymbolicLink(folder) { throw CacheError.unsafeFolder }
        let resolvedRoot = root.resolvingSymlinksInPath().path(percentEncoded: false)
        let resolvedArea = area.resolvingSymlinksInPath().path(percentEncoded: false)
        let prefix = resolvedRoot.hasSuffix("/") ? resolvedRoot : resolvedRoot + "/"
        guard resolvedArea.hasPrefix(prefix) else { throw CacheError.unsafeFolder }
        return area
    }

    /// The folder of an area, checked by `safeURL(for:)` and created when missing.
    public func prepare(_ area: CacheArea) throws -> URL {
        let url = try safeURL(for: area)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Applies each area's policy; run at launch. Returns one report per area (an unsafe area reports why it was skipped).
    @discardableResult
    public func evictAll(now: Date = .now) -> [CacheArea: CacheEvictionReport] {
        var reports: [CacheArea: CacheEvictionReport] = [:]
        for area in CacheArea.allCases {
            reports[area] = evict(area, policy: area.evictionPolicy, now: now)
        }
        return reports
    }

    /// Size in bytes of an area; 0 for an unsafe one.
    public func size(of area: CacheArea) -> Int {
        guard let url = try? safeURL(for: area) else { return 0 }
        return CacheEvictor.totalBytes(in: url)
    }

    /// Empties an area (the "clear caches" action), keeping its folder and removing every file whatever its date or size.
    @discardableResult
    public func clear(_ area: CacheArea) -> CacheEvictionReport {
        evict(area, policy: .everything, now: .now)
    }

    private func evict(_ area: CacheArea, policy: CacheEvictionPolicy, now: Date) -> CacheEvictionReport {
        guard let url = try? safeURL(for: area) else {
            var report = CacheEvictionReport()
            report.failures.append("\(area.rawValue): folder is a symbolic link or outside the cache, skipped")
            return report
        }
        return CacheEvictor.evict(directory: url, policy: policy, now: now)
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true
    }
}
