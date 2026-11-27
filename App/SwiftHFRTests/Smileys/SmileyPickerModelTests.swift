import Foundation
import HFRModels
import HFRParsing
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
        forumLoader: (@Sendable () async -> [ForumSmiley]?)? = nil,
        ownLoader: (@Sendable () async -> [OwnSmiley]?)? = nil
    ) -> SmileyPickerModel {
        SmileyPickerModel(
            catalogue: [entry(":)", editor: true), entry(":hidden:", editor: false), entry(":o", editor: true)],
            store: store, account: account, forumLoader: forumLoader, ownLoader: ownLoader
        )
    }

    private func forumSmiley(_ code: String) -> ForumSmiley {
        ForumSmiley(code: code, url: url(Self.base + "forum.gif"))
    }

    /// #1182: favourites from a newer build cannot be read; their section says so and, once the member confirmed, the store
    /// is set aside and a favourite can be added again.
    @Test func unreadableFavouritesCanBeDiscardedAndWrittenAgain() async {
        let persistence = InMemorySmallStorePersistence(
            AppSmileyFavoritesDocument(version: AppSmileyFavoritesDocument.currentVersion + 1)
        )
        let model = picker(store: AppSmileyFavoritesStore(persistence: persistence))
        await model.loadFavorites()
        #expect(model.favoritesAreUnreadable)
        #expect(model.sections.last?.state == .failed(SmileyPickerModel.unreadableFavoritesText))
        await model.discardUnreadableFavorites()
        #expect(!model.favoritesAreUnreadable)
        await model.setFavorite(favorite("[:fav]"), true)
        #expect(model.favorites.map(\.code) == ["[:fav]"])
        #expect(persistence.document?.accounts.isEmpty == false)
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

    @Test func sectionsComeInTheOperatorsOrder() async {
        let listed = [forumSmiley("[:forum]")]
        let model = picker(forumLoader: { listed })
        await model.loadForum()
        #expect(model.sections.map(\.kind) == [.basic, .forum, .own, .appFavorites])
        #expect(model.sections.map(\.title) == ["Smileys de base", "Smileys du forum", "Mes smileys", "Favoris de l’app"])
        #expect(model.sections[1].smileys.map(\.code) == ["[:forum]"])
    }

    // MARK: Mes smileys (#414)

    private func ownSmiley(_ code: String) -> OwnSmiley {
        OwnSmiley(code: code, imageURL: url(Self.base + "own.gif"))
    }

    /// The app favourites section, whatever its place among the others.
    private func appFavorites(of model: SmileyPickerModel) -> PickerSection {
        model.sections.first { $0.kind == .appFavorites } ?? PickerSection(kind: .appFavorites, smileys: [], state: .loading)
    }

    private func ownSmileys(_ codes: String...) -> [OwnSmiley] { codes.map(ownSmiley) }

    @Test func theOwnSectionIsLoadingThenListsTheMembersSmileys() async {
        let listed = ownSmileys("[:me]", "[:me:1]")
        let model = picker(ownLoader: { listed })
        #expect(model.sections[2].state == .loading)
        await model.loadOwn()
        #expect(model.sections[2].state == .smileys)
        #expect(model.sections[2].smileys.map(\.code) == ["[:me]", "[:me:1]"])
    }

    @Test func aMemberWithoutSmileysSeesHowToCreateOneNotAFailure() async {
        let model = picker(ownLoader: { [] })
        await model.loadOwn()
        #expect(model.sections[2].state == .empty(SmileyPickerModel.noOwnSmileysText))
    }

    @Test func aFailedReadIsShownAndRetriedNeverShownAsEmpty() async {
        let calls = LoadCounter()
        let listed = ownSmileys("[:me]")
        let model = picker(ownLoader: { await calls.next() == 1 ? nil : listed })
        await model.loadOwn()
        #expect(model.sections[2].state == .failed("Tes smileys sont indisponibles pour le moment."))
        await model.retryOwn()
        #expect(model.sections[2].smileys.map(\.code) == ["[:me]"])
        #expect(await calls.count == 2)
    }

    @Test func withoutALoaderTheOwnSectionSaysSoAndALoadedListIsNotReadTwice() async {
        let none = picker()
        await none.loadOwn()
        #expect(none.sections[2].state == .empty("Tes smileys sont indisponibles ici."))
        let calls = LoadCounter()
        let listed = ownSmileys("[:me]")
        let model = picker(ownLoader: { _ = await calls.next(); return listed })
        await model.loadOwn()
        await model.loadOwn()
        #expect(await calls.count == 1)
    }

    @Test func aTapOnOneOfTheMembersSmileysInsertsItAtOnce() async throws {
        let listed = ownSmileys("[:me]")
        let model = picker(ownLoader: { listed })
        await model.loadOwn()
        let smiley = try #require(model.sections[2].smileys.first)
        model.tap(own: smiley)
        #expect(model.chosen?.code == "[:me]")
    }

    @Test func theForumSectionIsLoadingThenListsTheAccountFavourites() async {
        let listed = [forumSmiley("[:a]"), forumSmiley("[:b:2]")]
        let model = picker(forumLoader: { listed })
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

    @Test func aFailedForumReadCanBeRetriedWithoutReopeningThePicker() async {
        let answers = LockedAnswers([nil, [forumSmiley("[:a]")]])
        let model = picker(forumLoader: { answers.next() })
        await model.loadForum()
        #expect(model.sections[1].state == .failed("Smileys du forum indisponibles pour le moment."))
        await model.retryForum()
        #expect(model.sections[1].state == .smileys)
        #expect(model.sections[1].smileys.map(\.code) == ["[:a]"])
    }

    @Test func anAccountWithoutForumFavouritesSaysSo() async {
        let model = picker(forumLoader: { [] })
        await model.loadForum()
        #expect(model.sections[1].state == .empty("Aucun smiley favori sur ton compte HFR."))
    }

    @Test func theEmptyAppFavouritesExplainHowToAddOne() {
        let section = appFavorites(of: picker())
        #expect(section.state == .empty(SmileyPickerModel.noFavoritesText))
        #expect(SmileyPickerModel.noFavoritesText.contains("Ajouter aux favoris"))
    }

    @Test func theContextMenuActionAddsThenRemovesAnyKindOfSmiley() async {
        let model = picker()
        let basic = model.basic[0]
        await model.toggleFavorite(basic)
        #expect(model.isFavorite(basic))
        #expect(appFavorites(of: model).smileys == [basic])
        await model.toggleFavorite(basic)
        #expect(!model.isFavorite(basic))
        #expect(appFavorites(of: model).state == .empty(SmileyPickerModel.noFavoritesText))
    }

    @Test func tappingAForumFavouriteOpensItsDetail() async {
        let listed = [forumSmiley("[:forum]")]
        let model = picker(forumLoader: { listed })
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

/// Scripted answers of a forum read, in order (the loader is `@Sendable`).
private final class LockedAnswers: @unchecked Sendable {
    private let lock = NSLock()
    private var answers: [[ForumSmiley]?]

    init(_ answers: [[ForumSmiley]?]) { self.answers = answers }

    func next() -> [ForumSmiley]? {
        lock.lock()
        defer { lock.unlock() }
        return answers.isEmpty ? nil : answers.removeFirst()
    }
}

/// Counts the reads of a scripted loader.
private actor LoadCounter {
    private(set) var count = 0
    func next() -> Int { count += 1; return count }
}
