import Foundation

/// The legacy on-device samples of #347: real legacy output on synthetic data (MANIFEST "Legacy on-device samples").
enum LegacySamples {
    static let folder = URL(filePath: #filePath)
        .deletingLastPathComponent() // LegacyImport
        .deletingLastPathComponent() // HFRStorageTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // HFRKit
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // repository
        .appending(path: "tooling/legacy-oracle/samples/legacy-stores", directoryHint: .isDirectory)

    static func data(_ name: String) throws -> Data {
        try Data(contentsOf: folder.appending(path: name))
    }

    /// A fresh temporary folder, removed by the caller.
    static func temporaryFolder() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: "legacy-import-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}
