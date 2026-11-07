import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// The picker's rules: the editor palette in catalogue order, favourites of the account only, legacy's messages, and a
/// tap on a basic smiley inserts at once while a favourite opens its detail.
@MainActor
struct SmileyPickerModelTests {
    private static let base = "https://forum-images.hardware.fr/icones/"

    private func entry(_ code: String, editor: Bool) -> CommonSmiley {
        CommonSmiley(code: code, url: url(Self.base + "x.gif"), resourceName: "x.gif", isEditorSmiley: editor)
    }

    private func favorite(_ code: String) -> PickerSmiley {
        PickerSmiley(code: code, imageURL: url(Self.base + "fav.gif"))
    }

    private func picker(
        store: AppSmileyFavoritesStore = AppSmileyFavoritesStore(persistence: InMemorySmallStorePersistence()),
        account: String = "user1",
        forumLoader: (@Sendable () async -> [ForumSmiley]?)? = nil
    ) -> SmileyPickerModel {
        SmileyPickerModel(
            catalogue: [entry(":)", editor: true), entry(":hidden:", editor: false), entry(":o", editor: true)],
            store: store, account: account, forumLoader: forumLoader
        )
    }

    private func forumSmiley(_ code: String) -> ForumSmiley {
        ForumSmiley(code: code, url: url(Self.base + "forum.gif"))
    }

    @Test func theBasicPaletteHoldsTheEditorSmileysInCatalogueOrder() {
        #expect(picker().basic.map(\.code) == [":)", ":o"])
    }

    @Test func theBundledCatalogueIsReadable() {
        let catalogue = SmileyPickerModel.bundledCatalogue()
        #expect(!catalogue.isEmpty)
        #expect(catalogue.contains { $0.isEditorSmiley })
    }

    @Test func tappingABasicSmileyChoosesItAtOnce() {
        let model = picker()
        model.tap(basic: model.basic[0])
        #expect(model.chosen?.code == ":)")
        #expect(model.presented == nil)
    }

    @Test func tappingAFavouriteOpensItsDetailAndInsertingChoosesIt() {
        let model = picker()
        let smiley = favorite("[:fav]")
        model.tap(favorite: smiley)
        #expect(model.presented == smiley)
        #expect(model.chosen == nil)
        model.insertPresented()
        #expect(model.chosen == smiley)
        #expect(model.presented == nil)
    }

    @Test func addingAFavouriteStoresItForTheAccountAndSaysSo() async {
        let store = AppSmileyFavoritesStore(persistence: InMemorySmallStorePersistence())
        let model = picker(store: store)
        let smiley = favorite("[:fav]")
        await model.setFavorite(smiley, true)
        #expect(model.favorites == [smiley])
        #expect(model.isFavorite(smiley))
        #expect(model.notice == "Smiley ajouté aux favoris")
        #expect(await store.contains(code: "[:fav]", account: "user1"))
        #expect(await store.favorites(for: "other").isEmpty)
    }

    @Test func removingAFavouriteClosesItsDetail() async {
        let model = picker()
        let smiley = favorite("[:fav]")
        await model.setFavorite(smiley, true)
        model.tap(favorite: smiley)
        await model.setFavorite(smiley, false)
        #expect(model.favorites.isEmpty)
        #expect(model.presented == nil)
        #expect(model.notice == "Smiley retiré des favoris")
    }

    @Test func favouritesAreReadWhenThePanelOpens() async {
        let store = AppSmileyFavoritesStore(persistence: InMemorySmallStorePersistence())
        _ = try? await store.add(code: "[:a]", url: url(Self.base + "a.gif"), account: "user1", at: Date(timeIntervalSince1970: 1))
        _ = try? await store.add(code: "[:b]", url: url(Self.base + "b.gif"), account: "user1", at: Date(timeIntervalSince1970: 2))
        let model = picker(store: store)
        #expect(model.favorites.isEmpty)
        await model.loadFavorites()
        #expect(model.favorites.map(\.code) == ["[:a]", "[:b]"])
    }

    @Test func aRefusedWriteSaysSoAndKeepsTheList() async {
        let model = picker(account: "")
        await model.setFavorite(favorite("[:fav]"), true)
        #expect(model.notice == "Erreur :/")
        #expect(model.favorites.isEmpty)
    }

    @Test func unreadableFavouritesSaySoAndWritesAreRefused() async {
        let store = AppSmileyFavoritesStore(persistence: UnreadableFavoritesPersistence())
        let model = picker(store: store)
        await model.loadFavorites()
        #expect(model.notice?.contains("illisibles") == true)
        #expect(model.favorites.isEmpty)
        await model.setFavorite(favorite("[:fav]"), true)
        #expect(model.notice == "Erreur :/")
    }

    // MARK: Sections and favourites (#600)

    @Test func sectionsComeInTheOperatorsOrderWithoutMySmileys() async {
        let model = picker(forumLoader: { [self.forumSmiley("[:forum]")] })
        await model.loadForum()
        #expect(model.sections.map(\.kind) == [.basic, .forum, .appFavorites])
        #expect(model.sections.map(\.title) == ["Smileys de base", "Smileys du forum", "Favoris de l’app"])
        #expect(model.sections[1].smileys.map(\.code) == ["[:forum]"])
    }

    @Test func theForumSectionIsLoadingThenListsTheAccountFavourites() async {
        let model = picker(forumLoader: { [self.forumSmiley("[:a]"), self.forumSmiley("[:b:2]")] })
        #expect(model.sections[1].state == .loading)
        await model.loadForum()
        #expect(model.sections[1].state == .smileys)
        #expect(model.sections[1].smileys.map(\.code) == ["[:a]", "[:b:2]"])
    }

    @Test func aFailedForumReadIsShownNotTurnedIntoAnEmptyList() async {
        let model = picker(forumLoader: { nil })
        await model.loadForum()
        #expect(model.sections[1].smileys.isEmpty)
        #expect(model.sections[1].state == .failed("Smileys du forum indisponibles pour le moment."))
    }

    @Test func anAccountWithoutForumFavouritesSaysSo() async {
        let model = picker(forumLoader: { [] })
        await model.loadForum()
        #expect(model.sections[1].state == .empty("Aucun smiley favori sur votre compte HFR."))
    }

    @Test func theEmptyAppFavouritesExplainHowToAddOne() {
        let section = picker().sections[2]
        #expect(section.state == .empty(SmileyPickerModel.noFavoritesText))
        #expect(SmileyPickerModel.noFavoritesText.contains("Ajouter aux favoris"))
    }

    @Test func theContextMenuActionAddsThenRemovesAnyKindOfSmiley() async {
        let model = picker()
        let basic = model.basic[0]
        await model.toggleFavorite(basic)
        #expect(model.isFavorite(basic))
        #expect(model.sections[2].smileys == [basic])
        await model.toggleFavorite(basic)
        #expect(!model.isFavorite(basic))
        #expect(model.sections[2].state == .empty(SmileyPickerModel.noFavoritesText))
    }

    @Test func tappingAForumFavouriteOpensItsDetail() async {
        let model = picker(forumLoader: { [self.forumSmiley("[:forum]")] })
        await model.loadForum()
        let smiley = model.sections[1].smileys[0]
        model.tap(forum: smiley)
        #expect(model.presented == smiley)
        #expect(model.chosen == nil)
    }
}

/// A favourites file that cannot be read: the store then refuses every write.
private struct UnreadableFavoritesPersistence: SmallStorePersistence {
    func load() throws -> AppSmileyFavoritesDocument? { throw CocoaError(.fileReadNoPermission) }
    func save(_ document: AppSmileyFavoritesDocument) throws {}
    func quarantineUnreadableData() throws {}
}
