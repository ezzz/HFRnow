import Foundation
import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Testing

/// A throwaway cache folder for a store under test.
struct OfflineTempCache {
    let cache: CacheDirectory

    init() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "offline-\(UUID().uuidString)", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        cache = CacheDirectory(root: root)
    }

    func cleanUp() { try? FileManager.default.removeItem(at: cache.root) }
}

/// Serves captured pages by page number, remembering what was asked (a page past `served` is answered by the last one, as R24).
final class FakeOfflineFetcher: OfflinePageFetching, @unchecked Sendable {
    private let lock = NSLock()
    private var asked: [Int] = []
    private let handler: @Sendable (Int) throws(ListLoadError) -> FetchedOfflinePage

    init(handler: @escaping @Sendable (Int) throws(ListLoadError) -> FetchedOfflinePage) {
        self.handler = handler
    }

    var requests: [Int] { lock.withLock { asked } }

    func fetch(topic: TopicID, page: Int) async throws(ListLoadError) -> FetchedOfflinePage {
        lock.withLock { asked.append(page) }
        return try handler(page)
    }
}

enum OfflineCorpus {
    static let pizza = TopicID(category: .forum(13), topic: 28563)

    static func html(_ file: String) throws -> String {
        try #require(String(bytes: try LiveTopicPageSourceTests.capture(file), encoding: .utf8))
    }
}
