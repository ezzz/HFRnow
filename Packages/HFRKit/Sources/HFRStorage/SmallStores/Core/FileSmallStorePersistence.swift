import Foundation

/// JSON file persistence with atomic writes, for any small store's document.
///
/// Dates use `JSONEncoder`'s default form (seconds since 2001, a plain JSON number on Darwin and Linux), which reads
/// back the exact same `Date`: seconds since 1970 shifts the low bits, which would change `RehostedImage.id` after a
/// relaunch. Legacy wrote `smileySearchHistory_v1` and `rehostImagesSwiftUI.json` with the same default.
public struct FileSmallStorePersistence<Document: SmallStoreDocument>: SmallStorePersistence {
    private let fileURL: URL

    /// Creates a persistence over `fileURL`; the parent directory is created on first save.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The file unreadable data is moved to.
    public var quarantineURL: URL {
        fileURL.appendingPathExtension("corrupt")
    }

    public func load() throws -> Document? {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return nil }
        let data = try Data(contentsOf: fileURL)
        // The version first: a newer format may not decode as this one, and must still be reported as newer.
        let version = try JSONDecoder().decode(VersionProbe.self, from: data).version
        guard version <= Document.currentVersion else { throw SmallStoreError.unsupportedVersion(version) }
        return try JSONDecoder().decode(Document.self, from: data)
    }

    public func save(_ document: Document) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(document)
        try FileManager.default.createDirectory(at: fileURL.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: fileURL, options: .atomic)
    }

    public func quarantineUnreadableData() throws {
        let manager = FileManager.default
        guard manager.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return }
        if manager.fileExists(atPath: quarantineURL.path(percentEncoded: false)) {
            // Never delete the earlier backup: keep it under a unique name.
            try manager.moveItem(at: quarantineURL, to: quarantineURL.appendingPathExtension(UUID().uuidString))
        }
        try manager.moveItem(at: fileURL, to: quarantineURL)
    }
}

/// The one field every small store document has, read before the rest.
private struct VersionProbe: Decodable {
    let version: Int
}
