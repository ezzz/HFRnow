import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// Upload history: legacy `rehostImagesSwiftUI.json` rules (newest at the top, removal by identity, no limit).
@Suite struct RehostUploadHistoryStoreTests {
    private static func image(_ name: String, at seconds: Double) throws -> RehostedImage {
        RehostedImage(
            fullURL: try #require(URL(string: "https://img.example/\(name).png")),
            miniURL: URL(string: "https://img.example/\(name).th.png"),
            width: 800,
            height: 600,
            uploadedAt: SmallStoreTestSupport.date(seconds)
        )
    }

    @Test func theLastImageAddedComesFirst() async throws {
        let store = RehostUploadHistoryStore(persistence: InMemorySmallStorePersistence())
        let first = try Self.image("one", at: 1)
        let second = try Self.image("two", at: 2)
        #expect(try await store.add(first))
        #expect(try await store.add(second))
        #expect(await store.images() == [second, first])
    }

    @Test func theSameImageIsNotAddedTwiceButAnotherUploadOfItIs() async throws {
        let persistence = FailingSmallStorePersistence<RehostUploadHistoryDocument>()
        let store = RehostUploadHistoryStore(persistence: persistence)
        let image = try Self.image("one", at: 1)
        try await store.add(image)
        #expect(try await !store.add(image))
        #expect(persistence.saveCount == 1)
        #expect(try await store.add(Self.image("one", at: 2)))
        #expect(await store.images().count == 2)
    }

    @Test func removalIsByIdentity() async throws {
        let store = RehostUploadHistoryStore(persistence: InMemorySmallStorePersistence())
        let first = try Self.image("one", at: 1)
        let again = try Self.image("one", at: 2)
        try await store.add(first)
        try await store.add(again)
        #expect(try await store.remove(id: first.id))
        #expect(await store.images() == [again])
        #expect(try await !store.remove(id: first.id))
    }

    @Test func anIdentityReadAfterARelaunchStillRemovesTheImage() async throws {
        let directory = try SmallStoreTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "uploads.json")
        let image = RehostedImage(
            fullURL: try #require(URL(string: "https://img.example/one.png")),
            uploadedAt: Date(timeIntervalSinceReferenceDate: 815_000_000.987_654_3)
        )
        try await RehostUploadHistoryStore(persistence: FileSmallStorePersistence(fileURL: file)).add(image)
        let reopened = RehostUploadHistoryStore(persistence: FileSmallStorePersistence(fileURL: file))
        #expect(await reopened.images().map(\.id) == [image.id])
        #expect(try await reopened.remove(id: image.id))
        #expect(await RehostUploadHistoryStore(persistence: FileSmallStorePersistence(fileURL: file)).images().isEmpty)
    }

    @Test func removalRemovesEveryEntryWithThatIdentity() async throws {
        let image = try Self.image("one", at: 1)
        let other = try Self.image("two", at: 2)
        let persistence = InMemorySmallStorePersistence(RehostUploadHistoryDocument(images: [image, other, image]))
        let store = RehostUploadHistoryStore(persistence: persistence)
        #expect(try await store.remove(id: image.id))
        #expect(await store.images() == [other])
        #expect(try await store.add(image))
    }
}
