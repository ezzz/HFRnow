import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// A failed load or save never loses stored positions and never crashes.
@Suite struct ReadingPositionStoreFailureTests {
    static let cuisine = TopicID(category: .forum(13), topic: 28563)

    private struct Unreadable: Error {}

    /// Fails to load (or to save) on demand.
    private final class FailingPersistence: ReadingPositionPersistence, @unchecked Sendable {
        // Tests drive one store from one task: no concurrent access.
        var failsToLoad = true
        var failsToSave = false
        var quarantined = false
        var saved: ReadingPositionDocument?

        func load() throws -> ReadingPositionDocument? {
            if failsToLoad { throw Unreadable() }
            return saved
        }

        func save(_ document: ReadingPositionDocument) throws {
            if failsToSave { throw Unreadable() }
            saved = document
        }

        func quarantineUnreadableData() throws {
            quarantined = true
            failsToLoad = false
        }
    }

    @Test func anUnreadableStoreAnswersNothingAndRefusesWrites() async throws {
        let persistence = FailingPersistence()
        let store = ReadingPositionStore(persistence: persistence)
        #expect(await store.position(of: Self.cuisine, account: "user1") == nil)
        #expect(await store.records(for: "user1").isEmpty)
        guard case .loadFailed = await store.loadFailure() else {
            Issue.record("Expected a load failure")
            return
        }
        await #expect(throws: ReadingPositionError.self) {
            try await store.advance(Self.cuisine, to: ReadingPosition(page: 2), account: "user1")
        }
        await #expect(throws: ReadingPositionError.self) { try await store.removeAccount("user1") }
        #expect(persistence.saved == nil)
    }

    @Test func discardSetsTheDataAsideAndStartsEmpty() async throws {
        let persistence = FailingPersistence()
        let store = ReadingPositionStore(persistence: persistence)
        try await store.discardUnreadableData()
        #expect(persistence.quarantined)
        #expect(await store.loadFailure() == nil)
        #expect(try await store.advance(Self.cuisine, to: ReadingPosition(page: 2), account: "user1"))
    }

    @Test func reloadRecoversOnceTheDataIsReadable() async throws {
        let persistence = FailingPersistence()
        let store = ReadingPositionStore(persistence: persistence)
        #expect(await store.loadFailure() != nil)
        persistence.failsToLoad = false
        persistence.saved = ReadingPositionDocument(accounts: [
            "user1": [ReadingPositionRecord(topic: Self.cuisine, position: ReadingPosition(page: 4))]
        ])
        #expect(await store.reload() == nil)
        #expect(await store.position(of: Self.cuisine, account: "user1")?.page == 4)
    }

    @Test func aNewerFormatIsNeverOverwritten() async throws {
        let persistence = InMemoryReadingPositionPersistence(ReadingPositionDocument(version: 2))
        let store = ReadingPositionStore(persistence: persistence)
        #expect(await store.loadFailure() == .unsupportedVersion(2))
        await #expect(throws: ReadingPositionError.unsupportedVersion(2)) {
            try await store.advance(Self.cuisine, to: ReadingPosition(page: 2), account: "user1")
        }
        #expect(persistence.document == ReadingPositionDocument(version: 2))
    }

    @Test func aFailedSaveLeavesMemoryUnchanged() async throws {
        let persistence = FailingPersistence()
        persistence.failsToLoad = false
        let store = ReadingPositionStore(persistence: persistence)
        try await store.advance(Self.cuisine, to: ReadingPosition(page: 2), account: "user1")
        persistence.failsToSave = true
        await #expect(throws: ReadingPositionError.self) {
            try await store.advance(Self.cuisine, to: ReadingPosition(page: 5), account: "user1")
        }
        #expect(await store.position(of: Self.cuisine, account: "user1")?.page == 2)
    }
}
