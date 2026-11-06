import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

@MainActor
struct FavoritesOptionsModelTests {
    @Test func emptyStoreShowsTheLegacyDefaults() {
        let options = FavoritesOptionsModel(settings: InMemorySettingsStore())
        #expect(options.mode == .flagsAndFavorites)
        #expect(options.groupedByCategory)
        #expect(!options.autoRefresh)
        #expect(!options.showsCollapsedSections)
    }

    @Test func everyChangeIsWrittenUnderItsLegacyKey() {
        let store = InMemorySettingsStore()
        let options = FavoritesOptionsModel(settings: store)
        options.mode = .favoritesOnly
        options.groupedByCategory = false
        options.autoRefresh = true
        options.showsCollapsedSections = true
        #expect(store.rawValue(forKey: "vos_sujets") == .string("1"))
        #expect(store.rawValue(forKey: "sujets_avec_cat") == .bool(false))
        #expect(store.rawValue(forKey: "favorites_auto_refresh") == .bool(true))
        #expect(store.rawValue(forKey: "FavoritesShowCollapsedSections") == .bool(true))
    }

    @Test func creatingTheModelWritesNothing() {
        let store = InMemorySettingsStore()
        _ = FavoritesOptionsModel(settings: store)
        #expect(store.rawValue(forKey: "vos_sujets") == nil)
        #expect(store.rawValue(forKey: "FavoritesShowCollapsedSections") == nil)
    }

    @Test func emptyCategoriesNeedTheFlagsAndFavouritesModeInBothSorts() {
        let options = FavoritesOptionsModel(settings: InMemorySettingsStore())
        options.showsCollapsedSections = true
        #expect(options.showsEmptySections)
        options.groupedByCategory = false
        #expect(options.showsEmptySections)
        options.mode = .favoritesOnly
        #expect(!options.showsEmptySections)
        options.mode = .flagsAndFavorites
        options.showsCollapsedSections = false
        #expect(!options.showsEmptySections)
    }

    @Test func settingsChangedElsewhereAreReadAgain() {
        let store = InMemorySettingsStore()
        let options = FavoritesOptionsModel(settings: store)
        store.set(true, for: SettingKey.favoritesAutoRefresh)
        #expect(!options.autoRefresh)
        options.reloadSettings()
        #expect(options.autoRefresh)
    }

    @Test func aFoldedSectionIsKeptAcrossModels() async {
        let layout = InMemorySmallStorePersistence<FavoritesLayoutDocument>()
        let first = favoritesOptions(layout: layout)
        await first.toggleCollapsed("cat:1")
        #expect(first.collapsedSections == ["cat:1"])
        #expect(layout.document?.collapsedSections == ["cat:1"])
        let second = favoritesOptions(layout: layout)
        await second.reload()
        #expect(second.collapsedSections == ["cat:1"])
        await second.toggleCollapsed("cat:1")
        #expect(second.collapsedSections.isEmpty)
        #expect(layout.document?.collapsedSections == [])
    }

    @Test func foldAllAndUnfoldAllTouchOnlyTheSectionsWithTopics() async {
        let layout = InMemorySmallStorePersistence<FavoritesLayoutDocument>()
        let options = favoritesOptions(layout: layout)
        let page = FavoritesPage(sections: [favoriteSection(1, [favoriteTopic(1, category: 1)]), favoriteSection(2, [])])
        #expect(options.hasCollapsibleSections(in: page))
        await options.collapseAll(in: page)
        #expect(options.collapsedSections == ["cat:1"])
        await options.expandAll()
        #expect(options.collapsedSections.isEmpty)
        options.groupedByCategory = false
        #expect(!options.hasCollapsibleSections(in: page))
    }

    @Test func superFavouritesBelongToTheAccountAndSurviveAReload() async {
        let supers = InMemorySmallStorePersistence<SuperFavoritesDocument>()
        let options = favoritesOptions(supers: supers)
        let topic = favoriteTopic(7, category: 1)
        await options.toggleSuperFavorite(topic)
        #expect(options.superFavorites == [TopicID(category: .forum(1), topic: 7)])
        let again = favoritesOptions(supers: supers)
        await again.reload()
        #expect(again.superFavorites == options.superFavorites)
        let other = favoritesOptions(account: "user2", supers: supers)
        await other.reload()
        #expect(other.superFavorites.isEmpty)
        await again.toggleSuperFavorite(topic)
        #expect(again.superFavorites.isEmpty)
    }

    @Test func withoutAnAccountNothingCanBeMarked() async {
        let supers = InMemorySmallStorePersistence<SuperFavoritesDocument>()
        let options = favoritesOptions(account: nil, supers: supers)
        #expect(!options.canMarkSuperFavorites)
        await options.toggleSuperFavorite(favoriteTopic(7))
        #expect(options.superFavorites.isEmpty)
        #expect(supers.document == nil)
    }

    @Test func aRowWithoutTopicIdentityCannotBeMarked() async {
        let options = favoritesOptions()
        await options.toggleSuperFavorite(TopicSummary(title: "x", path: "/x"))
        #expect(options.superFavorites.isEmpty)
    }

    @Test func pruneForgetsSectionsThePageNoLongerHasButNeverOnAnEmptyPage() async {
        let options = favoritesOptions()
        await options.toggleCollapsed("cat:1")
        await options.toggleCollapsed("cat:9")
        await options.prune(to: FavoritesPage())
        #expect(options.collapsedSections == ["cat:1", "cat:9"])
        await options.prune(to: FavoritesPage(sections: [favoriteSection(1, [favoriteTopic(1, category: 1)])]))
        #expect(options.collapsedSections == ["cat:1"])
    }

    @Test func groupsFollowTheOptions() async {
        let options = favoritesOptions()
        let page = FavoritesPage(sections: [
            favoriteSection(1, [favoriteTopic(1, category: 1)]), favoriteSection(2, [favoriteTopic(2, category: 2)])
        ])
        await options.toggleCollapsed("cat:1")
        #expect(options.groups(for: page).map(\.id) == ["cat:2"])
        options.showsCollapsedSections = true
        #expect(options.groups(for: page).map(\.id) == ["cat:1", "cat:2"])
    }
}
