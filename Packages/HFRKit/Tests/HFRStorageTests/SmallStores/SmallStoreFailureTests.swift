import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// A failed load or save never loses stored data, in every small store (the `PseudoListStore` rule).
@Suite struct SmallStoreFailureTests {
    static let cuisine = TopicID(category: .forum(13), topic: 28563)

    @Test func anUnreadableStoreAnswersNothingAndRefusesWrites() async throws {
        let persistence = FailingSmallStorePersistence<SuperFavoritesDocument>()
        persistence.failsToLoad = true
        let store = SuperFavoritesStore(persistence: persistence)
        #expect(await store.favorites(for: "user1").isEmpty)
        #expect(await !store.contains(Self.cuisine, account: "user1"))
        guard case .loadFailed = await store.loadFailure() else {
            Issue.record("Expected a load failure")
            return
        }
        await #expect(throws: SmallStoreError.self) { try await store.add(Self.cuisine, account: "user1") }
        await #expect(throws: SmallStoreError.self) { try await store.remove(Self.cuisine, account: "user1") }
        #expect(persistence.saveCount == 0)
    }

    @Test func discardSetsTheDataAsideAndStartsEmpty() async throws {
        let persistence = FailingSmallStorePersistence<SuperFavoritesDocument>()
        persistence.failsToLoad = true
        let store = SuperFavoritesStore(persistence: persistence)
        try await store.discardUnreadableData()
        #expect(persistence.quarantined)
        #expect(await store.loadFailure() == nil)
        #expect(try await store.add(Self.cuisine, account: "user1"))
    }

    @Test func discardDoesNothingWhenTheDataIsReadable() async throws {
        let persistence = FailingSmallStorePersistence<SuperFavoritesDocument>()
        let store = SuperFavoritesStore(persistence: persistence)
        try await store.add(Self.cuisine, account: "user1")
        try await store.discardUnreadableData()
        #expect(!persistence.quarantined)
        #expect(await store.contains(Self.cuisine, account: "user1"))
    }

    @Test func reloadRecoversOnceTheDataIsReadable() async throws {
        let persistence = FailingSmallStorePersistence<SuperFavoritesDocument>()
        persistence.failsToLoad = true
        let store = SuperFavoritesStore(persistence: persistence)
        #expect(await store.loadFailure() != nil)
        persistence.failsToLoad = false
        persistence.saved = SuperFavoritesDocument(accounts: ["user1": [SuperFavorite(topic: Self.cuisine, addedAt: .now)]])
        #expect(await store.reload() == nil)
        #expect(await store.contains(Self.cuisine, account: "user1"))
    }

    @Test func aNewerVersionIsNeverOverwritten() async throws {
        let newer = SmileySearchHistoryDocument(version: SmileySearchHistoryDocument.currentVersion + 1)
        let persistence = FailingSmallStorePersistence(newer)
        let store = SmileySearchHistoryStore(persistence: persistence)
        #expect(await store.loadFailure() == .unsupportedVersion(2))
        await #expect(throws: SmallStoreError.unsupportedVersion(2)) {
            try await store.record("chat", resultCount: 1)
        }
        #expect(persistence.saveCount == 0)
        #expect(persistence.saved == newer)
    }

    @Test func aFailedSaveLeavesMemoryUnchanged() async throws {
        let persistence = FailingSmallStorePersistence<RehostUploadHistoryDocument>()
        let store = RehostUploadHistoryStore(persistence: persistence)
        let image = RehostedImage(fullURL: try #require(URL(string: "https://img.example/one.png")), uploadedAt: .now)
        persistence.failsToSave = true
        await #expect(throws: SmallStoreError.self) { try await store.add(image) }
        #expect(await store.images().isEmpty)
        persistence.failsToSave = false
        #expect(try await store.add(image))
    }

    /// Each store over the same corrupt file: reads answer nothing, writes throw and the bytes stay as they were.
    @Test func aCorruptFileIsKeptByEveryStore() async throws {
        let directory = try SmallStoreTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "store.json")
        let garbage = Data("{not json".utf8)
        try garbage.write(to: file)
        let url = try #require(URL(string: "https://img.example/one.png"))

        let superFavorites = SuperFavoritesStore(persistence: FileSmallStorePersistence(fileURL: file))
        #expect(await superFavorites.favorites(for: "user1").isEmpty)
        await #expect(throws: SmallStoreError.self) { try await superFavorites.add(Self.cuisine, account: "user1") }

        let layout = FavoritesLayoutStore(persistence: FileSmallStorePersistence(fileURL: file))
        #expect(await layout.collapsedSections().isEmpty)
        await #expect(throws: SmallStoreError.self) { try await layout.setCollapsed(true, section: "13") }

        let smileys = AppSmileyFavoritesStore(persistence: FileSmallStorePersistence(fileURL: file))
        #expect(await smileys.favorites(for: "user1").isEmpty)
        await #expect(throws: SmallStoreError.self) { try await smileys.add(code: "[:exemple]", url: url, account: "user1") }

        let history = SmileySearchHistoryStore(persistence: FileSmallStorePersistence(fileURL: file))
        #expect(await history.recent(matching: "").isEmpty)
        await #expect(throws: SmallStoreError.self) { try await history.record("chat", resultCount: 1) }

        let uploads = RehostUploadHistoryStore(persistence: FileSmallStorePersistence(fileURL: file))
        #expect(await uploads.images().isEmpty)
        await #expect(throws: SmallStoreError.self) { try await uploads.add(RehostedImage(fullURL: url, uploadedAt: .now)) }

        #expect(try Data(contentsOf: file) == garbage)
        try await uploads.discardUnreadableData()
        #expect(try Data(contentsOf: directory.appending(path: "store.json.corrupt")) == garbage)
        #expect(try await uploads.add(RehostedImage(fullURL: url, uploadedAt: .now)))
    }
}
