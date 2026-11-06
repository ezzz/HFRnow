import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

@MainActor
struct FavoritesListModelTests {
    private func source() -> FakeDataSource {
        let source = FakeDataSource()
        source.favoritesHandler = { _ in
            FavoritesPage(sections: [
                favoriteSection(1, [favoriteTopic(1, category: 1, day: 1)]), favoriteSection(2, [favoriteTopic(2, category: 2, day: 2)])
            ])
        }
        return source
    }

    @Test func theLoadedPageIsLaidOutByTheOptions() async {
        let options = favoritesOptions()
        let model = TopicListModel(source: .favorites, dataSource: source(), favorites: options)
        await model.loadIfNeeded()
        #expect(model.displayedGroups.map(\.id) == ["cat:1", "cat:2"])
        options.groupedByCategory = false
        #expect(model.displayedGroups.map(\.id) == ["topics"])
        #expect(model.displayedGroups[0].topics.map(\.title) == ["Sujet 2", "Sujet 1"])
    }

    @Test func foldingEverySectionSaysSoInsteadOfShowingABlankList() async {
        let options = favoritesOptions()
        let model = TopicListModel(source: .favorites, dataSource: source(), favorites: options)
        await model.loadIfNeeded()
        #expect(!model.allSectionsHidden)
        await options.toggleCollapsed("cat:1")
        await options.toggleCollapsed("cat:2")
        #expect(model.allSectionsHidden)
        options.showsCollapsedSections = true
        #expect(!model.allSectionsHidden)
    }

    @Test func aGenuinelyEmptyListIsNotAllSectionsHidden() async {
        let model = TopicListModel(source: .favorites, dataSource: FakeDataSource(), favorites: favoritesOptions())
        await model.loadIfNeeded()
        #expect(!model.allSectionsHidden)
    }

    @Test func superFavouritesAreTintedOnAListThatHasOptions() async {
        let options = favoritesOptions()
        let model = TopicListModel(source: .favorites, dataSource: source(), favorites: options)
        await model.loadIfNeeded()
        let topic = favoriteTopic(1, category: 1)
        #expect(!model.isSuperFavorite(topic))
        await options.toggleSuperFavorite(topic)
        #expect(model.isSuperFavorite(topic))
        #expect(model.displayedGroups.first?.id == "super-favorites")
    }

    @Test func aForumListIgnoresTheFavouritesOptions() async {
        let model = TopicListModel(source: .forum(.forum(13), title: "D"), dataSource: FakeDataSource(), favorites: favoritesOptions())
        #expect(model.favorites == nil)
        await model.loadIfNeeded()
        #expect(model.displayedGroups.count == 1)
    }

    @Test func withoutAutoRefreshAReappearingListIsNotRequestedAgain() async {
        let data = source()
        let model = TopicListModel(source: .favorites, dataSource: data, favorites: favoritesOptions())
        await model.onAppear()
        await model.onAppear()
        #expect(data.requests == ["favorites:3"])
    }

    @Test func withAutoRefreshAReappearingListIsRequestedAgain() async {
        let options = favoritesOptions()
        options.autoRefresh = true
        let data = source()
        let model = TopicListModel(source: .favorites, dataSource: data, favorites: options)
        await model.onAppear()
        await model.onAppear()
        #expect(data.requests == ["favorites:3", "favorites:3"])
    }

    @Test func aLoadForgetsFoldedSectionsTheListNoLongerHas() async {
        let options = favoritesOptions()
        await options.toggleCollapsed("cat:9")
        let model = TopicListModel(source: .favorites, dataSource: source(), favorites: options)
        await model.loadIfNeeded()
        #expect(options.collapsedSections.isEmpty)
    }

    @Test func pickingAListIsTheFavouritesModeAndTheModeNamesTheStartList() {
        let store = InMemorySettingsStore()
        let options = FavoritesOptionsModel(settings: store)
        let navigation = NavigationModel(dataSource: FakeDataSource(), startupSource: TopicSource(mode: options.mode), favorites: options)
        #expect(navigation.selectedSource == .flagged)
        navigation.selectedSource = .favorites
        #expect(options.mode == .favoritesOnly)
        #expect(store.rawValue(forKey: "vos_sujets") == .string("1"))
        #expect(TopicSource(mode: .favoritesOnly) == .favorites)
        #expect(TopicSource(mode: .flagsAndFavorites) == .flagged)
    }
}

@MainActor
struct FavoritesModeSyncTests {
    @Test func aModeChangedInRéglagesSwitchesTheFavorisTabOnReload() async {
        let store = InMemorySettingsStore()
        let options = FavoritesOptionsModel(settings: store)
        let data = FakeDataSource()
        let forums = ForumListModel(dataSource: data)
        let root = RootModel(
            forums: forums, categories: NavigationModel(dataSource: data, forums: forums),
            favorites: NavigationModel(dataSource: data, forums: forums, startupSource: .flagged, favorites: options),
            messages: MessageListModel(source: FakePrivateMessages()), store: store, favoriteOptions: options
        )
        store.set(FavoritesSource.favoritesOnly, for: SettingKey.favoritesSource)
        root.reloadSettings()
        #expect(root.favorites.selectedSource == .favorites)
        #expect(options.mode == .favoritesOnly)
    }
}
