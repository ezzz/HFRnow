import Foundation
import HFRModels
import Synchronization
import Testing
@testable import HFRStorage

/// A clock the tests move by hand.
private final class TestClock: Sendable {
    private let current: Mutex<Date>
    init(_ start: Date) { current = Mutex(start) }
    var now: Date { current.withLock { $0 } }
    func advance(days: Double) { current.withLock { $0 = $0.addingTimeInterval(days * 86_400) } }
}

/// A persistence that holds a document and refuses every save.
private final class SaveRefusingPersistence: DraftPersistence {
    struct Refused: Error {}
    let stored: DraftDocument
    init(_ stored: DraftDocument) { self.stored = stored }
    func load() throws -> DraftDocument? { stored }
    func save(_ document: DraftDocument) throws { throw Refused() }
    func quarantineUnreadableData() throws {}
}

/// A store with the persistence and clock it runs on.
private struct Fixture {
    let store: DraftStore
    let persistence: InMemoryDraftPersistence
    let clock: TestClock
}

@Suite struct DraftStoreTests {
    private let topic = TopicID(category: .forum(13), topic: 4242)
    private let start = Date(timeIntervalSince1970: 1_761_000_000)

    private func makeStore(
        timeToLive: TimeInterval = 10 * 86_400,
        maximumCount: Int = 100
    ) -> Fixture {
        let persistence = InMemoryDraftPersistence()
        let clock = TestClock(start)
        let store = DraftStore(persistence: persistence, timeToLive: timeToLive, maximumCount: maximumCount, clock: { clock.now })
        return Fixture(store: store, persistence: persistence, clock: clock)
    }

    @Test func savedDraftComesBackWithItsSubject() async throws {
        let store = makeStore().store
        try await store.save("Bonjour", subject: "Titre", for: .newTopic(forum: .forum(13)), account: "me")
        let draft = await store.draft(for: .newTopic(forum: .forum(13)), account: "me")
        #expect(draft?.text == "Bonjour")
        #expect(draft?.subject == "Titre")
        #expect(draft?.updatedAt == start)
    }

    @Test func contextsAreIsolated() async throws {
        let store = makeStore().store
        try await store.save("reply p1", for: .reply(topic: topic, page: 1), account: "me")
        try await store.save("reply p2", for: .reply(topic: topic, page: 2), account: "me")
        try await store.save("edit", for: .edit(topic: topic, post: 5), account: "me")
        try await store.save("mp", for: .privateMessage(recipient: "Marc"), account: "me")
        try await store.save("topic", for: .newTopic(forum: .forum(13)), account: "me")
        #expect(await store.draft(for: .reply(topic: topic, page: 1), account: "me")?.text == "reply p1")
        #expect(await store.draft(for: .reply(topic: topic, page: 2), account: "me")?.text == "reply p2")
        #expect(await store.draft(for: .edit(topic: topic, post: 5), account: "me")?.text == "edit")
        #expect(await store.draft(for: .privateMessage(recipient: "marc"), account: "me")?.text == "mp")
        #expect(await store.draft(for: .newTopic(forum: .forum(14)), account: "me") == nil)
        #expect(await store.drafts(account: "me").count == 5)
    }

    @Test func draftsAreScopedPerAccount() async throws {
        let store = makeStore().store
        try await store.save("mine", for: .reply(topic: topic, page: 1), account: "Alice")
        #expect(await store.draft(for: .reply(topic: topic, page: 1), account: "alice")?.text == "mine")
        #expect(await store.draft(for: .reply(topic: topic, page: 1), account: "bob") == nil)
    }

    @Test func savingAgainReplacesInsteadOfDuplicating() async throws {
        let fixture = makeStore()
        let (store, persistence) = (fixture.store, fixture.persistence)
        try await store.save("one", for: .legacyGlobal, account: "me")
        try await store.save("two", for: .legacyGlobal, account: "me")
        #expect(persistence.document?.drafts.map(\.text) == ["two"])
    }

    @Test func savingEmptyContentRemovesTheDraftAndSkipsTheWriteWhenThereIsNone() async throws {
        let fixture = makeStore()
        let (store, persistence) = (fixture.store, fixture.persistence)
        try await store.save("", for: .legacyGlobal, account: "me")
        #expect(persistence.document == nil)
        try await store.save("text", for: .legacyGlobal, account: "me")
        try await store.save("", subject: "", for: .legacyGlobal, account: "me")
        #expect(await store.draft(for: .legacyGlobal, account: "me") == nil)
        #expect(persistence.document?.drafts.isEmpty == true)
    }

    @Test func aSubjectAloneIsADraft() async throws {
        let store = makeStore().store
        try await store.save("", subject: "Idée", for: .newTopic(forum: .forum(13)), account: "me")
        #expect(await store.draft(for: .newTopic(forum: .forum(13)), account: "me")?.subject == "Idée")
    }

    @Test func discardRemovesOnlyThatDraft() async throws {
        let store = makeStore().store
        try await store.save("a", for: .reply(topic: topic, page: 1), account: "me")
        try await store.save("b", for: .newTopic(forum: .forum(13)), account: "me")
        #expect(try await store.discard(for: .reply(topic: topic, page: 1), account: "me"))
        #expect(try await !store.discard(for: .reply(topic: topic, page: 1), account: "me"))
        #expect(await store.draft(for: .newTopic(forum: .forum(13)), account: "me")?.text == "b")
    }

    @Test func discardAllClearsOneAccountOnly() async throws {
        let store = makeStore().store
        try await store.save("a", for: .legacyGlobal, account: "me")
        try await store.save("b", for: .newTopic(forum: .forum(13)), account: "ME")
        try await store.save("c", for: .legacyGlobal, account: "other")
        #expect(try await store.discardAll(account: "me") == 2)
        #expect(await store.drafts(account: "me").isEmpty)
        #expect(await store.drafts(account: "other").count == 1)
    }

    @Test func expiredDraftsAreInvisibleThenPurged() async throws {
        let fixture = makeStore(timeToLive: 10 * 86_400)
        let (store, persistence, clock) = (fixture.store, fixture.persistence, fixture.clock)
        try await store.save("old", for: .legacyGlobal, account: "me")
        clock.advance(days: 5)
        try await store.save("newer", for: .newTopic(forum: .forum(13)), account: "me")
        clock.advance(days: 6)
        #expect(await store.draft(for: .legacyGlobal, account: "me") == nil)
        #expect(await store.draft(for: .newTopic(forum: .forum(13)), account: "me")?.text == "newer")
        #expect(persistence.document?.drafts.count == 2)
        #expect(try await store.purgeExpired() == 1)
        #expect(persistence.document?.drafts.map(\.text) == ["newer"])
        #expect(try await store.purgeExpired() == 0)
    }

    @Test func draftExactlyAtTheTimeToLiveIsStillLive() async throws {
        let fixture = makeStore(timeToLive: 10 * 86_400)
        let (store, clock) = (fixture.store, fixture.clock)
        try await store.save("edge", for: .legacyGlobal, account: "me")
        clock.advance(days: 10)
        #expect(await store.draft(for: .legacyGlobal, account: "me") != nil)
        clock.advance(days: 0.001)
        #expect(await store.draft(for: .legacyGlobal, account: "me") == nil)
    }

    @Test func savingPurgesExpiredDraftsFromTheFile() async throws {
        let fixture = makeStore(timeToLive: 10 * 86_400)
        let (store, persistence, clock) = (fixture.store, fixture.persistence, fixture.clock)
        try await store.save("old", for: .legacyGlobal, account: "me")
        clock.advance(days: 11)
        try await store.save("fresh", for: .newTopic(forum: .forum(13)), account: "me")
        #expect(persistence.document?.drafts.map(\.text) == ["fresh"])
    }

    @Test func theCountIsBoundedKeepingTheMostRecent() async throws {
        let fixture = makeStore(maximumCount: 3)
        let (store, persistence, clock) = (fixture.store, fixture.persistence, fixture.clock)
        for index in 1...5 {
            try await store.save("d\(index)", for: .edit(topic: topic, post: index), account: "me")
            clock.advance(days: 0.01)
        }
        #expect(Set(persistence.document?.drafts.map(\.text) ?? []) == ["d3", "d4", "d5"])
    }

    @Test func draftsListIsNewestFirst() async throws {
        let fixture = makeStore()
        let (store, clock) = (fixture.store, fixture.clock)
        try await store.save("first", for: .edit(topic: topic, post: 1), account: "me")
        clock.advance(days: 1)
        try await store.save("second", for: .edit(topic: topic, post: 2), account: "me")
        #expect(await store.drafts(account: "me").map(\.text) == ["second", "first"])
    }

    @Test func survivesANewStoreOverTheSamePersistence() async throws {
        let fixture = makeStore()
        let (store, persistence, clock) = (fixture.store, fixture.persistence, fixture.clock)
        try await store.save("kept", subject: "S", for: .privateMessage(recipient: "Marc"), account: "me")
        let reopened = DraftStore(persistence: persistence, clock: { clock.now })
        #expect(await reopened.draft(for: .privateMessage(recipient: "MARC"), account: "me")?.text == "kept")
    }

    @Test func concurrentSavesAreAllKept() async throws {
        let fixture = makeStore()
        let (store, persistence) = (fixture.store, fixture.persistence)
        try await withThrowingTaskGroup(of: Void.self) { group in
            for index in 0..<30 {
                group.addTask { try await store.save("t\(index)", for: .edit(topic: topic, post: index), account: "me") }
            }
            try await group.waitForAll()
        }
        #expect(persistence.document?.drafts.count == 30)
    }

    @Test func failedSaveLeavesTheLoadedDraftsUntouched() async throws {
        let existing = Draft(context: .legacyGlobal, account: "me", text: "kept", updatedAt: start)
        let store = DraftStore(
            persistence: SaveRefusingPersistence(DraftDocument(drafts: [existing])),
            clock: { start }
        )
        let failures = [
            await #expect(throws: DraftError.self) { try await store.save("lost", for: .legacyGlobal, account: "me") },
            await #expect(throws: DraftError.self) { try await store.save("other", for: .newTopic(forum: .forum(13)), account: "me") },
            await #expect(throws: DraftError.self) { try await store.discard(for: .legacyGlobal, account: "me") }
        ]
        for failure in failures {
            guard case .saveFailed? = failure else {
                Issue.record("expected saveFailed, got \(String(describing: failure))")
                continue
            }
        }
        #expect(await store.draft(for: .legacyGlobal, account: "me")?.text == "kept")
        #expect(await store.draft(for: .newTopic(forum: .forum(13)), account: "me") == nil)
        #expect(await store.drafts(account: "me").count == 1)
    }
}
