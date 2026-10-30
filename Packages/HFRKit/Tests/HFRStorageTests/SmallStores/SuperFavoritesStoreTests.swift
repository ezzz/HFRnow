import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// Super-favourites: legacy value rules (`Favorites.swift:112-136`), one list per account key.
@Suite struct SuperFavoritesStoreTests {
    static let cuisine = TopicID(category: .forum(13), topic: 28563)

    private static func makeStore() -> (SuperFavoritesStore, InMemorySmallStorePersistence<SuperFavoritesDocument>) {
        let persistence = InMemorySmallStorePersistence<SuperFavoritesDocument>()
        return (SuperFavoritesStore(persistence: persistence), persistence)
    }

    @Test func addContainsRemove() async throws {
        let (store, persistence) = Self.makeStore()
        #expect(await !store.contains(Self.cuisine, account: "user1"))
        #expect(try await store.add(Self.cuisine, account: "user1", at: SmallStoreTestSupport.date(1)))
        #expect(await store.contains(Self.cuisine, account: "user1"))
        #expect(persistence.document?.accounts["user1"] == [SuperFavorite(topic: Self.cuisine, addedAt: SmallStoreTestSupport.date(1))])
        #expect(try await store.remove(Self.cuisine, account: "user1"))
        #expect(await !store.contains(Self.cuisine, account: "user1"))
        #expect(try await !store.remove(Self.cuisine, account: "user1"))
    }

    @Test func aSecondAddChangesNothingAndKeepsTheFirstDate() async throws {
        let persistence = FailingSmallStorePersistence<SuperFavoritesDocument>()
        let store = SuperFavoritesStore(persistence: persistence)
        try await store.add(Self.cuisine, account: "user1", at: SmallStoreTestSupport.date(1))
        #expect(try await !store.add(Self.cuisine, account: "User1", at: SmallStoreTestSupport.date(2)))
        #expect(persistence.saveCount == 1)
        #expect(await store.favorites(for: "user1").map(\.addedAt) == [SmallStoreTestSupport.date(1)])
    }

    @Test func listsAreSavedSortedByCategoryThenNumber() async throws {
        let (store, persistence) = Self.makeStore()
        let topics = [
            TopicID(category: .forum(13), topic: 500),
            TopicID(category: .privateMessages, topic: 5),
            TopicID(category: .forum(13), topic: 20),
            TopicID(category: .forum(5), topic: 900)
        ]
        for topic in topics {
            try await store.add(topic, account: "user1", at: SmallStoreTestSupport.date(1))
        }
        let expected = [
            TopicID(category: .forum(5), topic: 900),
            TopicID(category: .forum(13), topic: 20),
            TopicID(category: .forum(13), topic: 500),
            TopicID(category: .privateMessages, topic: 5)
        ]
        #expect(persistence.document?.accounts["user1"]?.map(\.topic) == expected)
        #expect(await store.favorites(for: "user1").map(\.topic) == expected)
    }

    @Test func theSameNumberInAnotherCategoryIsAnotherTopic() async throws {
        let (store, _) = Self.makeStore()
        try await store.add(Self.cuisine, account: "user1")
        #expect(await !store.contains(TopicID(category: .forum(5), topic: 28563), account: "user1"))
        #expect(await !store.contains(TopicID(category: .privateMessages, topic: 28563), account: "user1"))
        #expect(try await store.add(TopicID(category: .forum(5), topic: 28563), account: "user1"))
        #expect(await store.favorites(for: "user1").count == 2)
    }

    @Test func accountsShareAListOnlyThroughTheirAccountKey() async throws {
        let (store, persistence) = Self.makeStore()
        try await store.add(Self.cuisine, account: "Us\u{200B}er1")
        #expect(await store.contains(Self.cuisine, account: "user1"))
        #expect(await store.contains(Self.cuisine, account: "USER1"))
        #expect(await !store.contains(Self.cuisine, account: "user2"))
        #expect(await !store.contains(Self.cuisine, account: " user1"))
        #expect(persistence.document?.accounts.keys.sorted() == ["user1"])
    }

    @Test func invalidInputIsRefusedBeforeAnythingIsSaved() async throws {
        let persistence = FailingSmallStorePersistence<SuperFavoritesDocument>()
        let store = SuperFavoritesStore(persistence: persistence)
        await #expect(throws: SmallStoreError.emptyAccount) { try await store.add(Self.cuisine, account: "\u{200B}") }
        await #expect(throws: SmallStoreError.emptyAccount) { try await store.remove(Self.cuisine, account: "") }
        for number in [0, -1] {
            await #expect(throws: SmallStoreError.invalidValue(reason: "topic number \(number)")) {
                try await store.add(TopicID(category: .forum(13), topic: number), account: "user1")
            }
        }
        #expect(persistence.saveCount == 0)
        #expect(await store.favorites(for: "").isEmpty)
    }

    @Test func removingTheLastTopicRemovesTheAccount() async throws {
        let (store, persistence) = Self.makeStore()
        try await store.add(Self.cuisine, account: "user1")
        try await store.add(Self.cuisine, account: "user2")
        try await store.remove(Self.cuisine, account: "user1")
        #expect(persistence.document?.accounts.keys.sorted() == ["user2"])
    }

    @Test func listsSurviveARelaunch() async throws {
        let directory = try SmallStoreTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "superfavorites.json")
        let first = SuperFavoritesStore(persistence: FileSmallStorePersistence(fileURL: file))
        try await first.add(Self.cuisine, account: "user1", at: SmallStoreTestSupport.date(0.3))
        let reopened = SuperFavoritesStore(persistence: FileSmallStorePersistence(fileURL: file))
        #expect(await reopened.favorites(for: "user1") == [SuperFavorite(topic: Self.cuisine, addedAt: SmallStoreTestSupport.date(0.3))])
    }
}
