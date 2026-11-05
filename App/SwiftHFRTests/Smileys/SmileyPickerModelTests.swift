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
        CommonSmiley(code: code, url: URL(string: Self.base + "x.gif")!, resourceName: "x.gif", isEditorSmiley: editor)
    }

    private func favorite(_ code: String) -> PickerSmiley {
        PickerSmiley(code: code, imageURL: URL(string: Self.base + "fav.gif")!)
    }

    private func picker(
        store: AppSmileyFavoritesStore = AppSmileyFavoritesStore(persistence: InMemorySmallStorePersistence()),
        account: String = "user1"
    ) -> SmileyPickerModel {
        SmileyPickerModel(
            catalogue: [entry(":)", editor: true), entry(":hidden:", editor: false), entry(":o", editor: true)],
            store: store, account: account
        )
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
        try? await store.add(code: "[:a]", url: URL(string: Self.base + "a.gif")!, account: "user1", at: Date(timeIntervalSince1970: 1))
        try? await store.add(code: "[:b]", url: URL(string: Self.base + "b.gif")!, account: "user1", at: Date(timeIntervalSince1970: 2))
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
}
