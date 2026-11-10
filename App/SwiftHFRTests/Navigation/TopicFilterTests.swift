import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

@MainActor
struct TopicFilterTests {
    private func model(
        _ source: TopicSource = .forum(.forum(13), title: "Discussions"), fake: FakeDataSource, filter: TopicFilterModel?,
        loggedIn: Bool = true
    ) -> TopicListModel {
        TopicListModel(source: source, dataSource: fake, isLoggedIn: { loggedIn }, topicFilter: filter)
    }

    @Test func theChoiceIsPersistedUnderTheLegacyKeyAndSharedByEveryList() {
        let store = InMemorySettingsStore()
        let first = TopicFilterModel(settings: store)
        #expect(first.flag == .all)
        first.flag = .tracked
        #expect(TopicFilterModel(settings: store).flag == .tracked)
        #expect(store.rawValue(forKey: "HFRswiftGlobalTopicListFlag") == .int(2))
    }

    @Test func aPersistedChoiceIsAskedFromHFRAtTheFirstLoad() async {
        let fake = FakeDataSource()
        let filter = TopicFilterModel(settings: InMemorySettingsStore([SettingKey.topicListFlag.key: .int(1)]))
        let list = model(fake: fake, filter: filter)
        await list.loadIfNeeded()
        #expect(fake.requests == ["topics:13:1:owntopic=3"])
        #expect(list.loadedFilter == .favorites)
    }

    @Test(arguments: [(TopicListFlag.favorites, 3), (.tracked, 1), (.read, 2)])
    func changingTheChoiceReloadsPageOneWithItsOwntopic(flag: TopicListFlag, owntopic: Int) async {
        let fake = FakeDataSource()
        let filter = TopicFilterModel(settings: InMemorySettingsStore())
        let list = model(fake: fake, filter: filter)
        await list.loadIfNeeded()
        await list.goToNextPage()
        filter.flag = flag
        await list.onAppear()
        #expect(fake.requests == ["topics:13:1", "topics:13:2", "topics:13:1:owntopic=\(owntopic)"])
        #expect(list.currentPage == 1)
    }

    @Test func aListThatStillMatchesTheChoiceIsNotReloaded() async {
        let fake = FakeDataSource()
        let list = model(fake: fake, filter: TopicFilterModel(settings: InMemorySettingsStore()))
        await list.loadIfNeeded()
        await list.onAppear()
        #expect(fake.requests == ["topics:13:1"])
    }

    @Test func loggedOutAsksForAllAndOffersNoFilter() async {
        let fake = FakeDataSource()
        let filter = TopicFilterModel(settings: InMemorySettingsStore([SettingKey.topicListFlag.key: .int(3)]))
        let list = model(fake: fake, filter: filter, loggedIn: false)
        await list.loadIfNeeded()
        #expect(fake.requests == ["topics:13:1"])
        #expect(!list.offersFilter)
        // The stored choice is kept for the next login.
        #expect(filter.flag == .read)
    }

    @Test func aSubforumHasNoFilterBecauseItsSubcatIsNotKnown() async {
        let fake = FakeDataSource()
        let filter = TopicFilterModel(settings: InMemorySettingsStore([SettingKey.topicListFlag.key: .int(1)]))
        let list = model(.subforum(path: "/hfr/Hardware/minipc/liste_sujet-1.htm", title: "Mini PC"), fake: fake, filter: filter)
        await list.loadIfNeeded()
        #expect(fake.requests == ["path:/hfr/Hardware/minipc/liste_sujet-1.htm:1"])
        #expect(!list.offersFilter)
    }

    @Test func aFilteredListShowsEveryRowAsFlagged() async {
        let fake = FakeDataSource()
        let filter = TopicFilterModel(settings: InMemorySettingsStore([SettingKey.topicListFlag.key: .int(2)]))
        let list = model(fake: fake, filter: filter)
        await list.loadIfNeeded()
        // Legacy `topicHasFlag`: with a filter on, every row is a flagged one (`MainWindow.swift:444-449`).
        #expect(list.hasFlag(topicSummary(10)))
        let plain = model(fake: fake, filter: nil)
        await plain.loadIfNeeded()
        #expect(!plain.hasFlag(topicSummary(10)))
    }

    @Test func theFavouritesTabHasNoFilter() async {
        let fake = FakeDataSource()
        let filter = TopicFilterModel(settings: InMemorySettingsStore())
        let list = TopicListModel(source: .favorites, dataSource: fake, isLoggedIn: { true }, topicFilter: filter)
        #expect(!list.offersFilter)
    }

    // Favoris: a category title opens that category with the list's own filter (legacy `headerTitleView`,
    // `Favorites.swift:344-372` @ 87fe0d1c; HFR's own header link carries the page's `owntopic`, R10 and P03c).
    private func favoritesNavigation(_ fake: FakeDataSource, filter: TopicFilterModel) -> NavigationModel {
        NavigationModel(
            dataSource: fake, sessionIsLoggedIn: { true }, startupSource: .favorites,
            favorites: FavoritesOptionsModel(settings: InMemorySettingsStore()),
            topicFilter: filter
        )
    }

    @Test func aSectionTitleOpensItsCategoryAndAGroupWithoutOneOpensNothing() {
        let page = FavoritesPage(sections: [
            FavoriteSection(
                forum: ForumLink(title: "Discussions", path: "/hfr/Discussions/liste_sujet-1.htm"), categoryID: .forum(13),
                topics: [topicSummary(1)]
            ),
            FavoriteSection(forum: ForumLink(title: "Sans id", path: "/hfr/X/liste_sujet-1.htm"), topics: [topicSummary(2)])
        ])
        let content = TopicListContent(favorites: page, isLoggedIn: true)
        #expect(content.groups.map(\.opens) == [
            .forum(.forum(13), title: "Discussions"), .subforum(path: "/hfr/X/liste_sujet-1.htm", title: "Sans id")
        ])
        #expect(TopicListContent(page: topicPage(page: 1), isLoggedIn: true).groups.first?.opens == nil)
    }

    @Test(arguments: [(FavoritesSource.favoritesOnly, TopicListFlag.favorites, 3), (.flagsAndFavorites, .tracked, 1)])
    func openingACategoryFromFavorisCarriesTheModesFilter(mode: FavoritesSource, flag: TopicListFlag, owntopic: Int) async {
        let fake = FakeDataSource()
        let filter = TopicFilterModel(settings: InMemorySettingsStore())
        let navigation = favoritesNavigation(fake, filter: filter)
        let category = TopicSource.forum(.forum(13), title: "Discussions")
        navigation.openCategory(category, mode: mode)
        #expect(navigation.openedCategory == category)
        #expect(filter.flag == flag)
        let list = navigation.topicList(for: category)
        await list.loadIfNeeded()
        #expect(fake.requests == ["topics:13:1:owntopic=\(owntopic)"])
        // Back in Favoris the selection is untouched: the category was pushed, not selected.
        #expect(navigation.selectedSource == .favorites)
    }
}
