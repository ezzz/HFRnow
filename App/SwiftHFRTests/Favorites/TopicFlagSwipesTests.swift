import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Testing

/// #869: the trailing swipe names the favourite by the row's state, and the super favourite is a second action in every list.
@MainActor
struct TopicFlagSwipesTests {
    /// The list kinds of the trailing swipe: a category (« Tous »), Drapeaux, Favoris.
    enum Kind: CaseIterable, Sendable {
        case forum, flagged, favorites

        var source: TopicSource {
            switch self {
            case .forum: .forum(.forum(13), title: "Discussions")
            case .flagged: .flagged
            case .favorites: .favorites
            }
        }
    }

    private func list(
        _ kind: Kind, _ topics: [TopicSummary], options: FavoritesOptionsModel? = favoritesOptions(),
        writer: FakeFlagWriter? = FakeFlagWriter(), topicFilter: TopicFilterModel? = nil
    ) async -> TopicListModel {
        let data = FakeDataSource()
        data.topicHandler = { _, _ in TopicListPage(topics: topics, navigation: PageNavigation(current: 1, last: 1)) }
        data.favoritesHandler = { _ in FavoritesPage(sections: [favoriteSection(13, topics)]) }
        // As `RootModel` builds them: a category list of Catégories gets the super-favourites alone, the favourites lists the options.
        let model = TopicListModel(
            source: kind.source, dataSource: data, isLoggedIn: { true }, favorites: kind == .forum ? nil : options,
            superFavorites: kind == .forum ? options : nil, flagActions: writer.map { TopicFlagActions(writer: $0) },
            topicFilter: topicFilter
        )
        await model.onAppear()
        return model
    }

    // MARK: - Favourite

    @Test(arguments: Kind.allCases)
    func aFavouriteRowOffersRetirerDesFavorisAndAnotherFlagKeepsSupprimer(kind: Kind) async {
        let favourite = flaggedTopic(1, flag: .yellow)
        let tracked = flaggedTopic(2, flag: .blue)
        let model = await list(kind, [favourite, tracked])
        #expect(model.canRemoveFlag(favourite) && model.isFavorite(favourite))
        #expect(model.removeFlagTitle(favourite) == "Retirer des favoris")
        #expect(model.canRemoveFlag(tracked))
        // Favoris holds favourites only (`owntopic=3`), whatever the row's icon.
        #expect(model.removeFlagTitle(tracked) == (kind == .favorites ? "Retirer des favoris" : "Supprimer"))
    }

    @Test func theFavorisFilterOfACategoryListsFavouritesOnly() async {
        let row = flaggedTopic(1, flag: nil)
        let stored = InMemorySettingsStore([SettingKey.topicListFlag.key: .int(TopicListFlag.favorites.rawValue)])
        let filter = TopicFilterModel(settings: stored)
        let model = await list(.forum, [row], topicFilter: filter)
        #expect(model.loadedFilter == .favorites)
        #expect(model.removeFlagTitle(row) == "Retirer des favoris")
    }

    /// A swipe sends one removal, confirmed by HFR; the row then is no favourite and offers no removal (the add half waits, #869).
    @Test(arguments: Kind.allCases)
    func retirerDesFavorisSendsOneWriteAndTheLabelFollows(kind: Kind) async throws {
        let writer = FakeFlagWriter()
        let favourite = flaggedTopic(1, flag: .yellow)
        let id = try #require(favourite.topicID)
        let model = await list(kind, [favourite], writer: writer)
        await model.removeFlag(favourite)
        #expect(writer.removed == [id])
        #expect(writer.added.isEmpty)
        #expect(!model.isFavorite(favourite) && !model.canRemoveFlag(favourite))
        #expect(model.actionFailure == nil)
    }

    @Test(arguments: Kind.allCases)
    func aRefusedRemovalKeepsTheFavouriteAndSaysWhy(kind: Kind) async {
        let writer = FakeFlagWriter()
        writer.removeHandler = { (_: TopicID) async throws(TopicFlagError) -> TopicFlagResult in throw .notLoggedIn }
        let favourite = flaggedTopic(1, flag: .yellow)
        let model = await list(kind, [favourite], writer: writer)
        await model.removeFlag(favourite)
        #expect(writer.removed.count == 1)
        #expect(model.isFavorite(favourite) && model.removeFlagTitle(favourite) == "Retirer des favoris")
        #expect(model.actionFailure == TopicFlagActions.reason(for: .notLoggedIn))
        #expect(model.actionFailureTitle == AlertTitles.flagRemoveFailed)
    }

    // MARK: - Super favourite

    @Test(arguments: Kind.allCases)
    func theSuperFavouriteIsOfferedInEveryListAndItsLabelFollowsTheStore(kind: Kind) async throws {
        let supers = InMemorySmallStorePersistence<SuperFavoritesDocument>()
        let row = flaggedTopic(1, flag: nil)
        let id = try #require(row.topicID)
        let model = await list(kind, [row], options: favoritesOptions(supers: supers))
        #expect(model.canToggleSuperFavorite(row))
        #expect(model.superFavoriteTitle(row) == "Ajouter aux super favoris")
        await model.toggleSuperFavorite(row)
        #expect(model.isMarkedSuperFavorite(row))
        #expect(model.superFavoriteTitle(row) == "Retirer des super favoris")
        #expect(supers.document?.accounts.values.flatMap { $0 }.map(\.topic) == [id])
        // The row's look stays legacy's: tinted in Favoris and Drapeaux only (`MainWindow` tints no super favourite).
        #expect(model.isSuperFavorite(row) == (kind != .forum))
        await model.toggleSuperFavorite(row)
        #expect(!model.isMarkedSuperFavorite(row))
        #expect(model.superFavoriteTitle(row) == "Ajouter aux super favoris")
        #expect(supers.document?.accounts.isEmpty != false)
        #expect(model.actionFailure == nil)
    }

    /// A category list shown before Favoris ever was reads the stored super favourites itself.
    @Test func aForumListReadsTheStoredSuperFavouritesWhenItShows() async throws {
        let supers = InMemorySmallStorePersistence<SuperFavoritesDocument>()
        let row = flaggedTopic(1, flag: nil)
        let id = try #require(row.topicID)
        _ = try await SuperFavoritesStore(persistence: supers).add(id, account: "user1")
        let model = await list(.forum, [row], options: favoritesOptions(supers: supers))
        #expect(model.isMarkedSuperFavorite(row))
        #expect(model.superFavoriteTitle(row) == "Retirer des super favoris")
    }

    /// The Catégories tab has no favourites options (its scope bar reads that), yet its lists offer the super favourite.
    @Test func theCategoriesTabListsOfferTheSuperFavourite() async {
        let options = favoritesOptions()
        let navigation = NavigationModel(dataSource: FakeDataSource(), superFavorites: options)
        #expect(navigation.favorites == nil)
        let list = navigation.topicList(for: Kind.forum.source)
        #expect(list.favorites == nil && list.superFavoriteOptions === options)
        #expect(list.canToggleSuperFavorite(flaggedTopic(1, flag: nil)))
        let favoris = NavigationModel(dataSource: FakeDataSource(), favorites: options).topicList(for: .favorites)
        #expect(favoris.superFavoriteOptions === options)
    }

    /// The app's own wiring: both tabs' lists share the root's options, the Catégories tab included (its `favorites` stays nil).
    @Test func theRootGivesBothTabsTheSameSuperFavourites() throws {
        let root = RootModel(environment: AppEnvironment.make(session: HFRSession(), accountName: nil), store: InMemorySettingsStore())
        let options = try #require(root.favoriteOptions)
        let category = root.categories.topicList(for: Kind.forum.source)
        #expect(category.favorites == nil && category.superFavoriteOptions === options)
        #expect(root.favorites.topicList(for: .favorites).superFavoriteOptions === options)
    }

    @Test(arguments: Kind.allCases)
    func noSuperFavouriteLoggedOutNorWithoutATopicNumber(kind: Kind) async {
        var numberless = flaggedTopic(2, flag: nil)
        numberless.topicID = nil
        let row = flaggedTopic(1, flag: nil)
        let loggedOut = await list(kind, [row], options: favoritesOptions(account: nil), writer: nil)
        #expect(!loggedOut.canToggleSuperFavorite(row))
        await loggedOut.toggleSuperFavorite(row)
        #expect(!loggedOut.isMarkedSuperFavorite(row))
        let model = await list(kind, [numberless])
        #expect(!model.canToggleSuperFavorite(numberless))
        let noOptions = await list(kind, [row], options: nil)
        #expect(!noOptions.canToggleSuperFavorite(row))
    }

    /// A refused store write changes nothing; a category list says why in its alert, the favourites lists in their strip.
    @Test(arguments: Kind.allCases)
    func aRefusedSuperFavouriteWriteKeepsTheRowAndSaysWhy(kind: Kind) async {
        let options = FavoritesOptionsModel(
            settings: InMemorySettingsStore(),
            stores: FavoritesStores(
                layout: FavoritesLayoutStore(persistence: InMemorySmallStorePersistence()),
                superFavorites: SuperFavoritesStore(persistence: RefusingSuperFavoritesPersistence()), account: "user1"
            )
        )
        let row = flaggedTopic(1, flag: nil)
        let model = await list(kind, [row], options: options)
        await model.toggleSuperFavorite(row)
        #expect(!model.isMarkedSuperFavorite(row))
        #expect(options.storeProblem == FavoritesOptionsModel.superWriteFailure)
        #expect(model.actionFailure == (kind == .forum ? FavoritesOptionsModel.superWriteFailure : nil))
        if kind == .forum { #expect(model.actionFailureTitle == AlertTitles.superFavoriteSaveFailed) }
    }
}

/// A super-favourites persistence whose writes are refused.
private struct RefusingSuperFavoritesPersistence: SmallStorePersistence {
    struct Refused: Error {}
    func load() throws -> SuperFavoritesDocument? { nil }
    func save(_ document: SuperFavoritesDocument) throws { throw Refused() }
    func quarantineUnreadableData() throws {}
}
