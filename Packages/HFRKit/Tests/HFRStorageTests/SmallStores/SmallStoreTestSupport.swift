import Foundation
@testable import HFRStorage

/// Helpers shared by the small store tests.
enum SmallStoreTestSupport {
    /// A fresh temporary directory; the caller removes it.
    static func makeDirectory() throws -> URL {
        let url = URL.temporaryDirectory.appending(path: "SmallStores-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// A date `seconds` after 2001-01-01, with a fraction so that rounding shows.
    static func date(_ seconds: Double) -> Date {
        Date(timeIntervalSinceReferenceDate: 800_000_000 + seconds)
    }
}

/// An error a persistence throws on demand.
struct SmallStoreTestFailure: Error {}

/// Fails to load or to save on demand, and counts saves.
final class FailingSmallStorePersistence<Document: SmallStoreDocument>: SmallStorePersistence, @unchecked Sendable {
    // Tests drive one store from one task: no concurrent access.
    var failsToLoad = false
    var failsToSave = false
    var quarantined = false
    var saved: Document?
    private(set) var saveCount = 0

    init(_ document: Document? = nil) {
        saved = document
    }

    func load() throws -> Document? {
        if failsToLoad { throw SmallStoreTestFailure() }
        return saved
    }

    func save(_ document: Document) throws {
        if failsToSave { throw SmallStoreTestFailure() }
        saved = document
        saveCount += 1
    }

    func quarantineUnreadableData() throws {
        quarantined = true
        failsToLoad = false
        saved = nil
    }
}
