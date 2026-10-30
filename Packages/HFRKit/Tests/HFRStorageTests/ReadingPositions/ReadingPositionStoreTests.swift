import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// `ReadingPositionStore`: forward-only advance, explicit reset, per-account isolation, eviction and removal.
@Suite struct ReadingPositionStoreTests {
    static let cuisine = TopicID(category: .forum(13), topic: 28563)
    static let thread = TopicID(category: .privateMessages, topic: 4242)
    static let start = Date(timeIntervalSince1970: 1_700_000_000)

    private func spot(_ page: Int, _ message: Int? = nil, minutes: Double = 0) -> ReadingPosition {
        ReadingPosition(page: page, messageNumber: message, updatedAt: Self.start.addingTimeInterval(minutes * 60))
    }

    @Test func advanceRecordsTheFirstPositionAndSavesIt() async throws {
        let persistence = InMemoryReadingPositionPersistence()
        let store = ReadingPositionStore(persistence: persistence)
        #expect(try await store.advance(Self.cuisine, to: spot(2, 500), account: "user1"))
        #expect(await store.position(of: Self.cuisine, account: "user1") == spot(2, 500))
        #expect(persistence.document?.accounts["user1"] == [ReadingPositionRecord(topic: Self.cuisine, position: spot(2, 500))])
        #expect(persistence.document?.version == ReadingPositionDocument.currentVersion)
    }

    @Test func advanceNeverMovesBackwards() async throws {
        let persistence = InMemoryReadingPositionPersistence()
        let store = ReadingPositionStore(persistence: persistence)
        try await store.advance(Self.cuisine, to: spot(3, 900), account: "user1")
        #expect(try await store.advance(Self.cuisine, to: spot(2, 500, minutes: 5), account: "user1") == false)
        #expect(try await store.advance(Self.cuisine, to: spot(3, 900, minutes: 5), account: "user1") == false)
        #expect(await store.position(of: Self.cuisine, account: "user1") == spot(3, 900))
        #expect(persistence.document?.accounts["user1"]?.first?.position == spot(3, 900))
        #expect(try await store.advance(Self.cuisine, to: spot(3, 950, minutes: 6), account: "user1"))
        #expect(await store.position(of: Self.cuisine, account: "user1") == spot(3, 950, minutes: 6))
    }

    @Test func resetMovesBackOnPurpose() async throws {
        let store = ReadingPositionStore(persistence: InMemoryReadingPositionPersistence())
        try await store.advance(Self.cuisine, to: spot(3, 900), account: "user1")
        #expect(try await store.reset(Self.cuisine, to: spot(1, minutes: 1), account: "user1"))
        #expect(await store.position(of: Self.cuisine, account: "user1") == spot(1, minutes: 1))
        #expect(try await store.reset(Self.cuisine, to: spot(1, minutes: 1), account: "user1") == false)
    }

    @Test func accountsAreKeptApartAndComparedExactly() async throws {
        let store = ReadingPositionStore(persistence: InMemoryReadingPositionPersistence())
        try await store.advance(Self.cuisine, to: spot(3), account: "user1")
        try await store.advance(Self.cuisine, to: spot(7), account: "user2")
        #expect(await store.position(of: Self.cuisine, account: "user1") == spot(3))
        #expect(await store.position(of: Self.cuisine, account: "user2") == spot(7))
        #expect(await store.position(of: Self.cuisine, account: "User1") == nil)
    }

    @Test func topicsAreKeyedByCategoryAndNumber() async throws {
        let store = ReadingPositionStore(persistence: InMemoryReadingPositionPersistence())
        let sameNumber = TopicID(category: .forum(5), topic: Self.cuisine.topic)
        try await store.advance(Self.cuisine, to: spot(3), account: "user1")
        #expect(await store.position(of: sameNumber, account: "user1") == nil)
        // A write to the same number in another category is a new record, not a move of the first one.
        #expect(try await store.advance(sameNumber, to: spot(1), account: "user1"))
        #expect(await store.position(of: sameNumber, account: "user1") == spot(1))
        #expect(await store.position(of: Self.cuisine, account: "user1") == spot(3))
        try await store.advance(Self.thread, to: spot(2), account: "user1")
        #expect(await store.position(of: Self.thread, account: "user1") == spot(2))
    }

    @Test func recordsAreNewestFirst() async throws {
        let store = ReadingPositionStore(persistence: InMemoryReadingPositionPersistence())
        try await store.advance(Self.cuisine, to: spot(1, minutes: 1), account: "user1")
        try await store.advance(Self.thread, to: spot(1, minutes: 2), account: "user1")
        #expect(await store.records(for: "user1").map(\.topic) == [Self.thread, Self.cuisine])
        try await store.advance(Self.cuisine, to: spot(2, minutes: 3), account: "user1")
        #expect(await store.records(for: "user1").map(\.topic) == [Self.cuisine, Self.thread])
    }

    @Test func theLeastRecentlyUpdatedTopicIsEvictedPerAccount() async throws {
        let store = ReadingPositionStore(persistence: InMemoryReadingPositionPersistence(), limitPerAccount: 3)
        for topic in 1...3 {
            try await store.advance(TopicID(category: .forum(13), topic: topic), to: spot(1, minutes: Double(topic)), account: "user1")
        }
        try await store.advance(Self.cuisine, to: spot(1, minutes: 9), account: "user2")
        // Topic 1 is read again, so topic 2 becomes the oldest.
        try await store.advance(TopicID(category: .forum(13), topic: 1), to: spot(2, minutes: 10), account: "user1")
        try await store.advance(TopicID(category: .forum(13), topic: 4), to: spot(1, minutes: 11), account: "user1")
        #expect(await store.records(for: "user1").map(\.topic.topic) == [4, 1, 3])
        #expect(await store.records(for: "user2").map(\.topic) == [Self.cuisine])
    }

    @Test func aNewTopicIsKeptEvenWhenItsDateIsTheOldest() async throws {
        let store = ReadingPositionStore(persistence: InMemoryReadingPositionPersistence(), limitPerAccount: 2)
        try await store.advance(TopicID(category: .forum(13), topic: 1), to: spot(1, minutes: 10), account: "user1")
        try await store.advance(TopicID(category: .forum(13), topic: 2), to: spot(1, minutes: 20), account: "user1")
        // The device clock went back: the record just written must survive its own eviction.
        try await store.advance(TopicID(category: .forum(13), topic: 3), to: spot(1, minutes: 0), account: "user1")
        #expect(Set(await store.records(for: "user1").map(\.topic.topic)) == [2, 3])
    }

    @Test func removeAndRemoveAccount() async throws {
        let persistence = InMemoryReadingPositionPersistence()
        let store = ReadingPositionStore(persistence: persistence)
        try await store.advance(Self.cuisine, to: spot(3), account: "user1")
        try await store.advance(Self.thread, to: spot(2), account: "user1")
        try await store.advance(Self.cuisine, to: spot(4), account: "user2")
        #expect(try await store.remove(Self.cuisine, account: "user1"))
        #expect(try await store.remove(Self.cuisine, account: "user1") == false)
        #expect(await store.position(of: Self.thread, account: "user1") == spot(2))
        #expect(try await store.remove(Self.thread, account: "user1"))
        #expect(persistence.document?.accounts["user1"] == nil)
        #expect(try await store.removeAccount("user2"))
        #expect(try await store.removeAccount("user2") == false)
        #expect(persistence.document?.accounts.isEmpty == true)
    }

    @Test func invalidInputIsRefusedUnsaved() async throws {
        let persistence = InMemoryReadingPositionPersistence()
        let store = ReadingPositionStore(persistence: persistence)
        await #expect(throws: ReadingPositionError.emptyAccount) {
            try await store.advance(Self.cuisine, to: spot(1), account: "")
        }
        await #expect(throws: ReadingPositionError.invalidPosition) {
            try await store.advance(Self.cuisine, to: spot(0), account: "user1")
        }
        await #expect(throws: ReadingPositionError.invalidPosition) {
            try await store.reset(TopicID(category: .forum(13), topic: 0), to: spot(1), account: "user1")
        }
        #expect(persistence.document == nil)
    }

    @Test func aLimitBelowOneKeepsOneTopic() async throws {
        let store = ReadingPositionStore(persistence: InMemoryReadingPositionPersistence(), limitPerAccount: 0)
        #expect(await store.limitPerAccount == 1)
        try await store.advance(Self.cuisine, to: spot(1), account: "user1")
        try await store.advance(Self.thread, to: spot(1, minutes: 1), account: "user1")
        #expect(await store.records(for: "user1").map(\.topic) == [Self.thread])
    }
}
