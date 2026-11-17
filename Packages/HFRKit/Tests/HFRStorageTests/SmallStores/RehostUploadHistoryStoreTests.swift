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

    // MARK: Removals and merge (#966)

    @Test func aRemovalIsRememberedWithItsDate() async throws {
        let persistence = FailingSmallStorePersistence<RehostUploadHistoryDocument>()
        let store = RehostUploadHistoryStore(persistence: persistence, clock: { SmallStoreTestSupport.date(50) })
        let image = try Self.image("one", at: 1)
        try await store.add(image)
        try await store.remove(id: image.id)
        #expect(persistence.saved?.removals == [RehostUploadRemoval(id: image.id, removedAt: SmallStoreTestSupport.date(50))])
        // Nothing removed, nothing remembered.
        #expect(try await !store.remove(id: "unknown"))
        #expect(persistence.saved?.removals.count == 1)
    }

    @Test func aMergeAddsTheOtherCopysUploadsAndAppliesItsRemovals() async throws {
        let kept = try Self.image("kept", at: 1)
        let removed = try Self.image("removed", at: 2)
        let incoming = try Self.image("incoming", at: 3)
        let store = RehostUploadHistoryStore(
            persistence: InMemorySmallStorePersistence(RehostUploadHistoryDocument(images: [removed, kept]))
        )
        let removal = RehostUploadRemoval(id: removed.id, removedAt: SmallStoreTestSupport.date(9))
        let merged = try await store.merge(images: [incoming, removed], removals: [removal])
        #expect(merged.images == [incoming, kept])
        #expect(merged.removals == [removal])
        #expect(await store.images() == [incoming, kept])
    }

    @Test func aRemovalBeyondTheKeptOnesStillDropsItsUploadInTheMergeThatSeesIt() throws {
        let images = try (1...150).map { try Self.image("n\($0)", at: Double($0)) }
        let removals = images.map { RehostUploadRemoval(id: $0.id, removedAt: $0.uploadedAt.addingTimeInterval(1_000)) }
        let merged = RehostUploadHistoryDocument(images: images).merging(images: [], removals: removals)
        #expect(merged.images.isEmpty)
        #expect(merged.removals.count == RehostUploadHistoryDocument.removalsLimit)
    }

    @Test func aMergeThatChangesNothingSavesNothingAndKeepsTheOrder() async throws {
        let older = try Self.image("older", at: 1)
        let newer = try Self.image("newer", at: 2)
        // Legacy's order, not the dates': kept as long as nothing comes from the other copy.
        let persistence = FailingSmallStorePersistence(RehostUploadHistoryDocument(images: [older, newer]))
        let store = RehostUploadHistoryStore(persistence: persistence)
        try await store.merge(images: [newer], removals: [])
        #expect(persistence.saveCount == 0)
        #expect(await store.images() == [older, newer])
    }

    @Test func everySavedChangeIsSignalled() async throws {
        let store = RehostUploadHistoryStore(persistence: InMemorySmallStorePersistence())
        var changes = await store.changes().makeAsyncIterator()
        let image = try Self.image("one", at: 1)
        try await store.add(image)
        #expect(await changes.next() != nil)
        try await store.merge(images: [Self.image("two", at: 2)], removals: [])
        #expect(await changes.next() != nil)
        try await store.remove(id: image.id)
        #expect(await changes.next() != nil)
    }

    /// The document as a build before #966 declared it.
    private struct DocumentBefore966: Codable {
        var version: Int
        var images: [RehostedImage]
    }

    @Test func aFileWrittenBeforeRemovalsReadsAndOneWithRemovalsStaysReadableByAnOlderBuild() throws {
        let image = try Self.image("one", at: 1)
        let before = try JSONEncoder().encode(DocumentBefore966(version: 1, images: [image]))
        let read = try JSONDecoder().decode(RehostUploadHistoryDocument.self, from: before)
        #expect(read == RehostUploadHistoryDocument(images: [image]))
        // Without removals, written exactly as before.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        #expect(try encoder.encode(read) == encoder.encode(DocumentBefore966(version: 1, images: [image])))

        let withRemovals = RehostUploadHistoryDocument(
            images: [image], removals: [RehostUploadRemoval(id: "gone", removedAt: SmallStoreTestSupport.date(2))]
        )
        let older = try JSONDecoder().decode(DocumentBefore966.self, from: JSONEncoder().encode(withRemovals))
        #expect(older.images == [image])
        #expect(older.version == RehostUploadHistoryDocument.currentVersion)
    }
}
