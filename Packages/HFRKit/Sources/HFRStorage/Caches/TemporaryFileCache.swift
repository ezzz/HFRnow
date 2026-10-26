import Foundation

/// Short-lived files that a web view loads from disk, such as rendered topic pages.
///
/// Legacy wrote `topic-<UUID>.htm` for every page view and never removed it (audit E §7.10). Files here are removed by
/// `CacheArea.topicPages`' policy (one day, 20 MB) when `CacheDirectory.evictAll()` runs at launch.
public struct TemporaryFileCache: Sendable {
    private let cache: CacheDirectory

    /// Creates a temporary file cache in the `pages` area of `cache`.
    public init(cache: CacheDirectory) {
        self.cache = cache
    }

    /// The folder to grant read access to when loading a file into a web view.
    public var directoryURL: URL {
        cache.url(for: .topicPages)
    }

    /// Writes `data` to a new uniquely named file and returns its URL.
    public func write(_ data: Data, prefix: String = "topic", pathExtension: String = "htm") throws -> URL {
        // A prefix or extension with a separator or "." could place the file outside the pages folder, where no policy reaches it.
        guard Self.isSafeComponent(prefix), Self.isSafeComponent(pathExtension) else { throw CacheError.invalidFileName }
        let directory = try cache.prepare(.topicPages)
        let url = directory
            .appending(path: "\(prefix)-\(UUID().uuidString)", directoryHint: .notDirectory)
            .appendingPathExtension(pathExtension)
        try data.write(to: url, options: .atomic)
        return url
    }

    /// Writes a string as UTF-8.
    public func write(_ text: String, prefix: String = "topic", pathExtension: String = "htm") throws -> URL {
        try write(Data(text.utf8), prefix: prefix, pathExtension: pathExtension)
    }

    private static func isSafeComponent(_ text: String) -> Bool {
        !text.isEmpty && text.count <= 32 && text.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }
    }
}
