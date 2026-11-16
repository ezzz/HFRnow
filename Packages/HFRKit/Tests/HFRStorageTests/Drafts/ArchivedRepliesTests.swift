import Foundation
import HFRModels
import Synchronization
import Testing
@testable import HFRStorage

/// Archived replies per topic (LOT-101): the rules of legacy `ReplyDraftStore` (`AnswerView.swift:137-244` @ 87fe0d1c).
@Suite struct ArchivedRepliesTests {
    private let topic = TopicID(category: .forum(13), topic: 4242)
    private let other = TopicID(category: .forum(13), topic: 77)
    private let start = Date(timeIntervalSince1970: 1_761_000_000)

    private final class Clock: Sendable {
        private let current: Mutex<Date>
        init(_ start: Date) { current = Mutex(start) }
        var now: Date { current.withLock { $0 } }
        func advance(seconds: Double) { current.withLock { $0 = $0.addingTimeInterval(seconds) } }
    }

    private func makeStore(clock: Clock, persistence: InMemoryDraftPersistence = InMemoryDraftPersistence()) -> DraftStore {
        DraftStore(persistence: persistence, clock: { clock.now })
    }

    @Test func archivedRepliesComeBackNewestFirstWithTheirSource() async throws {
        let clock = Clock(start)
        let store = makeStore(clock: clock)
        try await store.archiveReply("first", topic: topic, source: .quickReply, account: "me")
        clock.advance(seconds: 60)
        try await store.archiveReply("second", topic: topic, source: .quote, account: "me")
        let list = await store.archivedReplies(topic: topic, account: "me")
        #expect(list.map(\.text) == ["second", "first"])
        #expect(list.map(\.source) == [.quote, .quickReply])
        #expect(list.first?.archivedAt == start.addingTimeInterval(60))
    }

    @Test func atMostThreePerTopicTheOldestGo() async throws {
        let clock = Clock(start)
        let store = makeStore(clock: clock)
        for text in ["a", "b", "c", "d"] {
            try await store.archiveReply(text, topic: topic, source: .quickReply, account: "me")
            clock.advance(seconds: 1)
        }
        #expect(await store.archivedReplies(topic: topic, account: "me").map(\.text) == ["d", "c", "b"])
    }

    @Test func sameInstantKeepsInsertionOrder() async throws {
        let store = makeStore(clock: Clock(start))
        for text in ["a", "b", "c", "d"] {
            try await store.archiveReply(text, topic: topic, source: .quickReply, account: "me")
        }
        #expect(await store.archivedReplies(topic: topic, account: "me").map(\.text) == ["d", "c", "b"])
    }

    @Test func theLimitIsPerTopicAndPerAccount() async throws {
        let clock = Clock(start)
        let store = makeStore(clock: clock)
        for text in ["a", "b", "c"] {
            try await store.archiveReply(text, topic: topic, source: .quickReply, account: "me")
            try await store.archiveReply(text, topic: other, source: .quickReply, account: "me")
            try await store.archiveReply(text, topic: topic, source: .quickReply, account: "Marc")
        }
        try await store.archiveReply("d", topic: topic, source: .quickReply, account: "me")
        #expect(await store.archivedReplies(topic: topic, account: "me").map(\.text) == ["d", "c", "b"])
        #expect(await store.archivedReplies(topic: other, account: "me").count == 3)
        #expect(await store.archivedReplies(topic: topic, account: "marc").count == 3)
    }

    @Test func theSameTextAgainReplacesItInsteadOfDoubling() async throws {
        let clock = Clock(start)
        let store = makeStore(clock: clock)
        try await store.archiveReply("hello", topic: topic, source: .quickReply, account: "me")
        try await store.archiveReply("other", topic: topic, source: .quickReply, account: "me")
        clock.advance(seconds: 5)
        try await store.archiveReply("  hello\n", topic: topic, source: .quote, account: "me")
        let list = await store.archivedReplies(topic: topic, account: "me")
        #expect(list.map(\.text) == ["  hello\n", "other"])
        #expect(list.first?.source == .quote)
    }

    @Test func blankTextIsNeverArchivedAndWritesNothing() async throws {
        let persistence = InMemoryDraftPersistence()
        let store = makeStore(clock: Clock(start), persistence: persistence)
        #expect(try await store.archiveReply("", topic: topic, source: .quickReply, account: "me") == nil)
        #expect(try await store.archiveReply(" \n\t", topic: topic, source: .quickReply, account: "me") == nil)
        #expect(await store.archivedReplies(topic: topic, account: "me").isEmpty)
        #expect(try persistence.load() == nil)
    }

    @Test func discardOneAndDiscardAllOnlyTouchTheirTopic() async throws {
        let store = makeStore(clock: Clock(start))
        let first = try #require(try await store.archiveReply("a", topic: topic, source: .quickReply, account: "me"))
        try await store.archiveReply("b", topic: topic, source: .quickReply, account: "me")
        try await store.archiveReply("c", topic: other, source: .quickReply, account: "me")
        #expect(try await store.discardArchivedReply(id: first.id, topic: topic, account: "me"))
        #expect(try await store.discardArchivedReply(id: first.id, topic: topic, account: "me") == false)
        #expect(await store.archivedReplies(topic: topic, account: "me").map(\.text) == ["b"])
        #expect(try await store.discardArchivedReplies(topic: topic, account: "me") == 1)
        #expect(await store.archivedReplies(topic: topic, account: "me").isEmpty)
        #expect(await store.archivedReplies(topic: other, account: "me").count == 1)
    }

    @Test func theActiveReplyDraftIsNotAnArchivedOneAndSurvivesEveryArchiveOperation() async throws {
        let store = makeStore(clock: Clock(start))
        try await store.save("active", for: .reply(topic: topic, page: 1), account: "me")
        try await store.archiveReply("set aside", topic: topic, source: .quickReply, account: "me")
        #expect(await store.archivedReplies(topic: topic, account: "me").map(\.text) == ["set aside"])
        try await store.discardArchivedReplies(topic: topic, account: "me")
        #expect(await store.draft(for: .reply(topic: topic, page: 1), account: "me")?.text == "active")
        // And the other way round: discarding the active draft (after a send) leaves the archive.
        try await store.archiveReply("kept", topic: topic, source: .quickReply, account: "me")
        try await store.discard(for: .reply(topic: topic, page: 1), account: "me")
        #expect(await store.archivedReplies(topic: topic, account: "me").map(\.text) == ["kept"])
    }

    @Test func archivedRepliesSurviveARestartAndExpireLikeDrafts() async throws {
        let clock = Clock(start)
        let persistence = InMemoryDraftPersistence()
        try await makeStore(clock: clock, persistence: persistence)
            .archiveReply("kept", topic: topic, source: .quote, account: "me")
        let reopened = makeStore(clock: clock, persistence: persistence)
        #expect(await reopened.archivedReplies(topic: topic, account: "me").map(\.text) == ["kept"])
        clock.advance(seconds: DraftStore.defaultTimeToLive + 1)
        #expect(await reopened.archivedReplies(topic: topic, account: "me").isEmpty)
    }

    @Test func logoutRemovesThem() async throws {
        let store = makeStore(clock: Clock(start))
        try await store.archiveReply("a", topic: topic, source: .quickReply, account: "me")
        try await store.discardAll(account: "me")
        #expect(await store.archivedReplies(topic: topic, account: "me").isEmpty)
    }

    @Test func aFailedWriteLeavesTheListAsItWas() async throws {
        struct Refused: Error {}
        final class Refusing: DraftPersistence {
            let stored: DraftDocument
            init(_ stored: DraftDocument) { self.stored = stored }
            func load() throws -> DraftDocument? { stored }
            func save(_ document: DraftDocument) throws { throw Refused() }
            func quarantineUnreadableData() throws {}
        }
        let store = DraftStore(persistence: Refusing(DraftDocument()), clock: { start })
        await #expect(throws: DraftError.self) {
            try await store.archiveReply("a", topic: topic, source: .quickReply, account: "me")
        }
        #expect(await store.archivedReplies(topic: topic, account: "me").isEmpty)
    }

    @Test func theNewContextSurvivesTheFileRoundTrip() throws {
        let draft = Draft(
            context: .archivedReply(topic: topic, id: UUID(), source: .quote), account: "me", text: "x", updatedAt: start
        )
        let data = try JSONEncoder().encode(DraftDocument(drafts: [draft]))
        #expect(try JSONDecoder().decode(DraftDocument.self, from: data).drafts == [draft])
    }
}
