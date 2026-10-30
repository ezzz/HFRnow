import Foundation
import Testing
@testable import HFRStorage

/// App smiley favourites: legacy `smiley_favorites_cache2` rules (`SmileyCache.m:350-439`), one list per account key.
@Suite struct AppSmileyFavoritesStoreTests {
    private static func url(_ name: String) throws -> URL {
        try #require(URL(string: "https://forum-images.hardware.fr/images/perso/\(name).gif"))
    }

    @Test func addContainsRemove() async throws {
        let persistence = InMemorySmallStorePersistence<AppSmileyFavoritesDocument>()
        let store = AppSmileyFavoritesStore(persistence: persistence)
        let url = try Self.url("exemple")
        #expect(try await store.add(code: "[:exemple]", url: url, account: "user1", at: SmallStoreTestSupport.date(1)))
        #expect(await store.contains(code: "[:exemple]", account: "user1"))
        let expected = AppSmileyFavorite(code: "[:exemple]", url: url, addedAt: SmallStoreTestSupport.date(1))
        #expect(persistence.document?.accounts["user1"] == [expected])
        #expect(try await store.remove(code: "[:exemple]", account: "user1"))
        #expect(await !store.contains(code: "[:exemple]", account: "user1"))
        #expect(try await !store.remove(code: "[:exemple]", account: "user1"))
        #expect(persistence.document?.accounts.isEmpty == true)
    }

    @Test func aCodeAlreadyThereKeepsItsURLAndDateAndSavesNothing() async throws {
        let persistence = FailingSmallStorePersistence<AppSmileyFavoritesDocument>()
        let store = AppSmileyFavoritesStore(persistence: persistence)
        try await store.add(code: "[:exemple]", url: try Self.url("exemple"), account: "user1", at: SmallStoreTestSupport.date(1))
        #expect(try await !store.add(code: "[:exemple]", url: try Self.url("autre"), account: "USER1", at: SmallStoreTestSupport.date(2)))
        #expect(persistence.saveCount == 1)
        let stored = await store.favorites(for: "user1")
        #expect(stored.map(\.url) == [try Self.url("exemple")])
        #expect(stored.map(\.addedAt) == [SmallStoreTestSupport.date(1)])
    }

    @Test func codesAreComparedExactly() async throws {
        let store = AppSmileyFavoritesStore(persistence: InMemorySmallStorePersistence())
        try await store.add(code: "[:exemple]", url: try Self.url("exemple"), account: "user1")
        #expect(await !store.contains(code: "[:Exemple]", account: "user1"))
        #expect(await !store.contains(code: " [:exemple]", account: "user1"))
        #expect(try await store.add(code: "[:Exemple]", url: try Self.url("exemple"), account: "user1"))
        #expect(await store.favorites(for: "user1").count == 2)
    }

    @Test func theListIsOldestFirstEvenWhenTheClockMovedBack() async throws {
        let store = AppSmileyFavoritesStore(persistence: InMemorySmallStorePersistence())
        let url = try Self.url("exemple")
        try await store.add(code: "[:a]", url: url, account: "user1", at: SmallStoreTestSupport.date(100))
        try await store.add(code: "[:b]", url: url, account: "user1", at: SmallStoreTestSupport.date(50))
        try await store.add(code: "[:c]", url: url, account: "user1", at: SmallStoreTestSupport.date(100))
        try await store.add(code: "[:d]", url: url, account: "user1", at: SmallStoreTestSupport.date(200))
        try await store.add(code: "[:e]", url: url, account: "user1", at: SmallStoreTestSupport.date(10))
        #expect(await store.favorites(for: "user1").map(\.code) == ["[:e]", "[:b]", "[:a]", "[:c]", "[:d]"])
    }

    @Test func accountsHaveTheirOwnList() async throws {
        let persistence = InMemorySmallStorePersistence<AppSmileyFavoritesDocument>()
        let store = AppSmileyFavoritesStore(persistence: persistence)
        try await store.add(code: "[:exemple]", url: try Self.url("exemple"), account: "User\u{200B}1")
        #expect(await store.contains(code: "[:exemple]", account: "user1"))
        #expect(await !store.contains(code: "[:exemple]", account: "user2"))
        #expect(persistence.document?.accounts.keys.sorted() == ["user1"])
    }

    @Test func invalidInputIsRefusedBeforeAnythingIsSaved() async throws {
        let persistence = FailingSmallStorePersistence<AppSmileyFavoritesDocument>()
        let store = AppSmileyFavoritesStore(persistence: persistence)
        let url = try Self.url("exemple")
        await #expect(throws: SmallStoreError.invalidValue(reason: "empty smiley code")) {
            try await store.add(code: " \n", url: url, account: "user1")
        }
        await #expect(throws: SmallStoreError.emptyAccount) { try await store.add(code: "[:exemple]", url: url, account: "") }
        await #expect(throws: SmallStoreError.emptyAccount) { try await store.remove(code: "[:exemple]", account: "\u{200B}") }
        #expect(persistence.saveCount == 0)
    }

    @Test func aListStoredByAnotherWriterIsReadAsLegacyLoadedIt() async throws {
        let url = try Self.url("exemple")
        let date = SmallStoreTestSupport.date
        let stored = AppSmileyFavoritesDocument(accounts: ["user1": [
            AppSmileyFavorite(code: "[:b]", url: url, addedAt: date(2)),
            AppSmileyFavorite(code: "[:a]", url: url, addedAt: date(1)),
            AppSmileyFavorite(code: "[:c]", url: url, addedAt: date(3)),
            AppSmileyFavorite(code: "[:e]", url: url, addedAt: date(2)),
            AppSmileyFavorite(code: "[:b]", url: url, addedAt: date(0))
        ]])
        let persistence = InMemorySmallStorePersistence(stored)
        let store = AppSmileyFavoritesStore(persistence: persistence)
        #expect(await store.favorites(for: "user1").map(\.code) == ["[:a]", "[:b]", "[:e]", "[:c]"])
        try await store.add(code: "[:d]", url: url, account: "user1", at: date(1.5))
        #expect(persistence.document?.accounts["user1"]?.map(\.code) == ["[:a]", "[:d]", "[:b]", "[:e]", "[:c]"])
        let other = AppSmileyFavoritesStore(persistence: InMemorySmallStorePersistence(stored))
        #expect(try await other.remove(code: "[:b]", account: "user1"))
        #expect(await !other.contains(code: "[:b]", account: "user1"))
    }
}
