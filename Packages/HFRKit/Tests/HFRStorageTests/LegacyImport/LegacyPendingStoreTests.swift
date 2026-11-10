import Foundation
import HFRModels
@testable import HFRStorage
import Testing

@Suite("Legacy pending lists (LOT-067, D1 and D2)")
struct LegacyPendingStoreTests {
    private let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    private let day: TimeInterval = 24 * 60 * 60

    private struct Stores {
        let pending: LegacyPendingStore
        let superFavorites: SuperFavoritesStore
        let drafts: DraftStore
    }

    private func topic(_ category: Int, _ number: Int) -> TopicID {
        TopicID(category: .forum(category), topic: number)
    }

    private func stores() -> Stores {
        Stores(
            pending: LegacyPendingStore(persistence: InMemorySmallStorePersistence<LegacyPendingDocument>()),
            superFavorites: SuperFavoritesStore(persistence: InMemorySmallStorePersistence<SuperFavoritesDocument>()),
            drafts: DraftStore(persistence: InMemoryDraftPersistence(), clock: { [start] in start })
        )
    }

    @Test("a pending number becomes a super-favourite in every category the favourites list shows it in, then leaves")
    func resolveSuperFavorites() async throws {
        let stores = stores()
        let pending = stores.pending, superFavorites = stores.superFavorites
        #expect(try await pending.addSuperFavorites([777, 12, 0, -1, 12], account: "User1", at: start) == 2)
        #expect(await pending.pendingSuperFavorites(for: "user1") == [12, 777])

        let added = try await pending.resolveSuperFavorites(
            listed: [topic(13, 777), topic(25, 777), topic(13, 5)], account: "USER1", into: superFavorites, now: start
        )

        #expect(added == 2)
        #expect(await superFavorites.favorites(for: "user1").map(\.topic) == [topic(13, 777), topic(25, 777)])
        #expect(await pending.pendingSuperFavorites(for: "user1") == [12])
        #expect(await superFavorites.favorites(for: "user2").isEmpty)
    }

    @Test("a pending super-favourite expires after 90 days and is forgotten when the user empties super-favourites")
    func superFavoritesExpiryAndDiscard() async throws {
        let stores = stores()
        let pending = stores.pending, superFavorites = stores.superFavorites
        try await pending.addSuperFavorites([1, 2], account: "user1", at: start)
        let late = start.addingTimeInterval(90 * day + 1)
        #expect(try await pending.resolveSuperFavorites(listed: [topic(1, 1)], account: "user1", into: superFavorites, now: late) == 0)
        #expect(await pending.pendingSuperFavorites(for: "user1").isEmpty)

        try await pending.addSuperFavorites([3], account: "user1", at: start)
        let onTime = start.addingTimeInterval(90 * day)
        #expect(try await pending.resolveSuperFavorites(listed: [], account: "user1", into: superFavorites, now: onTime) == 0)
        #expect(await pending.pendingSuperFavorites(for: "user1") == [3])
        try await pending.discardPendingSuperFavorites(account: "user1")
        #expect(await pending.pendingSuperFavorites(for: "user1").isEmpty)
    }

    @Test("a failing super-favourites store keeps the numbers pending")
    func superFavoritesDestinationFailure() async throws {
        let pending = stores().pending
        try await pending.addSuperFavorites([4], account: "user1", at: start)
        let broken = SuperFavoritesStore(persistence: InMemorySmallStorePersistence(SuperFavoritesDocument(version: 99)))
        await #expect(throws: SmallStoreError.unsupportedVersion(99)) {
            try await pending.resolveSuperFavorites(listed: [topic(1, 4)], account: "user1", into: broken, now: start)
        }
        #expect(await pending.pendingSuperFavorites(for: "user1") == [4])
    }

    @Test("opening a topic turns its pending draft into the ordinary reply draft, once")
    func resolveReplyDraft() async throws {
        let stores = stores()
        let pending = stores.pending, drafts = stores.drafts
        let added = try await pending.addReplyDrafts([
            PendingReplyDraft(number: 42, text: "Brouillon", updatedAt: start),
            PendingReplyDraft(number: 42, text: "second", updatedAt: start),
            PendingReplyDraft(number: 7, text: " ", updatedAt: start)
        ], account: "user1", at: start)
        #expect(added == 1)
        let context = DraftContext.reply(topic: topic(13, 42), page: 3)

        let newTopic = DraftContext.newTopic(forum: .forum(13))
        #expect(try await pending.resolveReplyDraft(for: newTopic, account: "user1", into: drafts, now: start) == false)
        #expect(try await pending.resolveReplyDraft(for: context, account: "user1", into: drafts, now: start))
        #expect(await drafts.draft(for: context, account: "user1")?.text == "Brouillon")
        #expect(await pending.pendingReplyDrafts(for: "user1").isEmpty)
        #expect(try await pending.resolveReplyDraft(for: context, account: "user1", into: drafts, now: start) == false)
    }

    @Test("a draft already written in SwiftHFR wins; the pending one is dropped")
    func existingDraftWins() async throws {
        let stores = stores()
        let pending = stores.pending, drafts = stores.drafts
        let context = DraftContext.reply(topic: topic(13, 42), page: 1)
        try await drafts.save("nouveau", for: context, account: "user1")
        try await pending.addReplyDrafts([PendingReplyDraft(number: 42, text: "ancien", updatedAt: start)], account: "user1", at: start)
        #expect(try await pending.resolveReplyDraft(for: context, account: "user1", into: drafts, now: start) == false)
        #expect(await drafts.draft(for: context, account: "user1")?.text == "nouveau")
        #expect(await pending.pendingReplyDrafts(for: "user1").isEmpty)
    }

    @Test("a pending draft expires 30 days after legacy saved it; an expired one is never set aside")
    func replyDraftExpiry() async throws {
        let stores = stores()
        let pending = stores.pending, drafts = stores.drafts
        let old = PendingReplyDraft(number: 1, text: "vieux", updatedAt: start.addingTimeInterval(-31 * day))
        #expect(try await pending.addReplyDrafts([old], account: "user1", at: start) == 0)
        try await pending.addReplyDrafts([PendingReplyDraft(number: 2, text: "frais", updatedAt: start)], account: "user1", at: start)
        let late = start.addingTimeInterval(30 * day + 1)
        let context = DraftContext.reply(topic: topic(1, 2), page: 1)
        #expect(try await pending.resolveReplyDraft(for: context, account: "user1", into: drafts, now: late) == false)
        #expect(await pending.pendingReplyDrafts(for: "user1").isEmpty)
    }

    @Test("an empty account is refused")
    func emptyAccount() async {
        let pending = stores().pending
        await #expect(throws: SmallStoreError.emptyAccount) { try await pending.addSuperFavorites([1], account: "\u{200B}", at: start) }
    }
}
