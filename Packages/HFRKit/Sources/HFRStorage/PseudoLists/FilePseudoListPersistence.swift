import Foundation

/// JSON file persistence with atomic writes.
public struct FilePseudoListPersistence: PseudoListPersistence {
    private let fileURL: URL

    /// Creates a persistence over `fileURL`; the parent directory is created on first save.
    public init(fileURL: URL) {
        self.fileURL = fileURL
    }

    /// The file unreadable data is moved to.
    public var quarantineURL: URL {
        fileURL.appendingPathExtension("corrupt")
    }

    public func load() throws -> PseudoListDocument? {
        guard FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else { return nil }
        let data = try Data(contentsOf: fileURL)
        return try JSONDecoder().decode(PseudoListDocument.self, from: data)
    }

    public func save(_ document: PseudoListDocument) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
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
