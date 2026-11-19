import Foundation

/// JSON file persistence with atomic writes.
public struct FileReadingPositionPersistence: ReadingPositionPersistence {
    private let fileURL: URL

    /// Creates a persistence over `fileURL`; the parent directory is created on first save.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The file unreadable data is moved to.
    public var quarantineURL: URL {
        fileURL.appendingPathExtension("corrupt")
    }

    public func load() throws -> ReadingPositionDocument? {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return nil }
        let data = try Data(contentsOf: fileURL)
        // The version first, as the small stores do (#1184): a newer file is "update the app" whatever its shape.
        let version = try StoredVersion.read(data)
        guard version <= ReadingPositionDocument.currentVersion else { throw ReadingPositionError.unsupportedVersion(version) }
        guard version >= 1 else { throw ReadingPositionError.loadFailed(reason: "invalid version \(version)") }
        return try Self.decoder.decode(ReadingPositionDocument.self, from: data)
    }

    public func save(_ document: ReadingPositionDocument) throws {
        let data = try Self.encoder.encode(document)
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

    /// Dates as seconds since 1970, a plain JSON number: the same on Darwin and Linux.
    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.dateEncodingStrategy = .secondsSince1970
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
