import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// LOT-158: what the import left pending reaches the screens: super-favourites at the favourites load, a reply draft when
/// its topic opens and when the composer starts (LOT-067 D1, D2).
@MainActor
struct LegacyPendingPlacementTests {
    private func pendingStore() -> LegacyPendingStore {
        LegacyPendingStore(persistence: InMemorySmallStorePersistence())
    }

    private func favorites(account: String?, pending: LegacyPendingStore) -> FavoritesOptionsModel {
        FavoritesOptionsModel(
            settings: InMemorySettingsStore(),
            stores: FavoritesStores(
                layout: FavoritesLayoutStore(persistence: InMemorySmallStorePersistence()),
                superFavorites: SuperFavoritesStore(persistence: InMemorySmallStorePersistence()), account: account, pending: pending
            )
        )
    }

    private func favoritesSource() -> FakeDataSource {
        let source = FakeDataSource()
        source.favoritesHandler = { _ in
            FavoritesPage(sections: [
                favoriteSection(1, [favoriteTopic(7, category: 1), favoriteTopic(8, category: 1)]),
                favoriteSection(2, [favoriteTopic(7, category: 2)])
            ])
        }
        return source
    }

    @Test func pendingSuperFavouritesArePlacedInEveryCategoryTheLoadedListShows() async throws {
        let pending = pendingStore()
        try await pending.addSuperFavorites([7, 99], account: "user1", at: Date())
        let options = favorites(account: "user1", pending: pending)
        let model = TopicListModel(source: .favorites, dataSource: favoritesSource(), favorites: options)
        await model.loadIfNeeded()
        #expect(options.superFavorites == [TopicID(category: .forum(1), topic: 7), TopicID(category: .forum(2), topic: 7)])
        #expect(model.displayedGroups.first?.id == "super-favorites")
        // A number the list does not show waits for a later load.
        #expect(await pending.pendingSuperFavorites(for: "user1") == [99])
    }

    @Test func withoutAnAccountNothingPendingIsPlaced() async throws {
        let pending = pendingStore()
        try await pending.addSuperFavorites([7], account: "user1", at: Date())
        let options = favorites(account: nil, pending: pending)
        let model = TopicListModel(source: .favorites, dataSource: favoritesSource(), favorites: options)
        await model.loadIfNeeded()
        #expect(options.superFavorites.isEmpty)
        #expect(await pending.pendingSuperFavorites(for: "user1") == [7])
    }

    private func pendingDraft(_ text: String, in pending: LegacyPendingStore) async throws {
        try await pending.addReplyDrafts(
            [PendingReplyDraft(number: readerTopic.topic, text: text, updatedAt: Date())], account: ComposerFixture.account, at: Date()
        )
    }

    @Test func theComposerStartsOnTheLegacyDraftOfItsTopic() async throws {
        let pending = pendingStore()
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        try await pendingDraft("Brouillon de HFR+", in: pending)
        var services = ComposerFixture.services(poster: ScriptedPoster([]), drafts: drafts)
        services.legacyDrafts = LegacyDraftResolver(pending: pending, drafts: drafts, account: ComposerFixture.account)
        let composer = ReplyComposerModel(target: replyTarget, services: services, autosaveDelay: .seconds(60))
        await composer.start()
        #expect(composer.text == "Brouillon de HFR+")
        #expect(await pending.pendingReplyDrafts(for: ComposerFixture.account).isEmpty)
    }

    @Test func aSwiftHFRDraftOfTheTopicWinsOverTheLegacyOne() async throws {
        let pending = pendingStore()
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        try await pendingDraft("Brouillon de HFR+", in: pending)
        try await drafts.save("Brouillon récent", for: replyTarget.draftContext, account: ComposerFixture.account)
        var services = ComposerFixture.services(poster: ScriptedPoster([]), drafts: drafts)
        services.legacyDrafts = LegacyDraftResolver(pending: pending, drafts: drafts, account: ComposerFixture.account)
        let composer = ReplyComposerModel(target: replyTarget, services: services, autosaveDelay: .seconds(60))
        await composer.start()
        #expect(composer.text == "Brouillon récent")
    }

    @Test func openingTheTopicMakesTheLegacyDraftItsReplyDraft() async throws {
        let pending = pendingStore()
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        try await pendingDraft("Brouillon de HFR+", in: pending)
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic), page: 2), source: FakeTopicPages())
        reader.legacyDrafts = LegacyDraftResolver(pending: pending, drafts: drafts, account: ComposerFixture.account)
        await reader.onAppear()
        await reader.legacyDraftTask?.value
        let stored = await drafts.draft(for: ReplyTarget.draftContext(of: readerTopic), account: ComposerFixture.account)
        #expect(stored?.text == "Brouillon de HFR+")
        #expect(replyTarget.draftContext == ReplyTarget.draftContext(of: readerTopic))
    }
}
