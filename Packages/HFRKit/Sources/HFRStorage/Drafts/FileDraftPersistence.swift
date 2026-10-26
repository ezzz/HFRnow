import Foundation

/// JSON file persistence with atomic writes.
public struct FileDraftPersistence: DraftPersistence {
    private let fileURL: URL

    /// Creates a persistence over `fileURL`; the parent directory is created on first save.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The file undecodable data is moved to.
    public var quarantineURL: URL {
        fileURL.appendingPathExtension("corrupt")
    }

    public func load() throws -> DraftDocument? {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder.drafts.decode(DraftDocument.self, from: data)
    }

    public func save(_ document: DraftDocument) throws {
        let data = try JSONEncoder.drafts.encode(document)
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

extension JSONEncoder {
    /// Encoder of the draft file: stable key order, ISO 8601 dates.
    fileprivate static var drafts: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

extension JSONDecoder {
    /// Decoder of the draft file.
    fileprivate static var drafts: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
