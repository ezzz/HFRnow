import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

@MainActor
struct RootModelTests {
    private func model(
        store: InMemorySettingsStore = InMemorySettingsStore(), unread: Int? = 3, loggedIn: Bool = true
    ) async -> RootModel {
        let source = FakeDataSource()
        source.forumHandler = { ForumListPage(forums: [], isLoggedIn: loggedIn, unreadPrivateMessages: unread) }
        let forums = ForumListModel(dataSource: source)
        let root = RootModel(
            forums: forums,
            categories: NavigationModel(dataSource: source, forums: forums),
            favorites: NavigationModel(dataSource: source, forums: forums, startupSource: .favorites),
            store: store
        )
        await forums.loadIfNeeded()
        return root
    }

    @Test func tabsKeepTheLegacyOrderTitlesAndIcons() {
        #expect(RootTab.allCases.map(\.title) == ["Catégories", "Favoris", "Messages", "Plus"])
        #expect(RootTab.allCases.map(\.symbol) == ["folder.fill", "star.fill", "envelope", "ellipsis"])
    }

    @Test func startScreenPicksTheTabAndFavouritesIsTheDefault() async {
        #expect(await model().selectedTab == .favorites)
        for (screen, tab) in [(StartupScreen.categories, RootTab.categories), (.favorites, .favorites), (.messages, .messages)] {
            let store = InMemorySettingsStore()
            store.set(screen, for: SettingKey.startupScreen)
            let root = await model(store: store)
            #expect(root.selectedTab == tab)
            #expect(root.selectedDestination == .tab(tab))
        }
    }

    @Test func tabBarAndSidebarShareOneSelection() async {
        let root = await model()
        root.selectedDestination = .tab(.messages)
        #expect(root.selectedTab == .messages)
        root.selectedTab = .categories
        #expect(root.selectedDestination == .tab(.categories))
        root.selectedDestination = .plus(.settings)
        #expect(root.selectedTab == .more)
        root.selectedTab = .more
        #expect(root.selectedDestination == .plus(.settings))
        root.selectedTab = .favorites
        #expect(root.selectedDestination == .tab(.favorites))
    }

    @Test func theMessagesBadgeShowsTheUnreadCountFromTheHomePage() async {
        #expect(await model(unread: 3).unreadPrivateMessages == 3)
        #expect(await model(unread: nil, loggedIn: false).unreadPrivateMessages == 0)
        #expect(await model(unread: 0).unreadPrivateMessages == 0)
    }

    @Test func theBadgeSettingHidesTheBadge() async {
        let store = InMemorySettingsStore()
        store.set(false, for: SettingKey.privateMessageBadge)
        #expect(await model(store: store, unread: 5).unreadPrivateMessages == 0)
    }

    @Test func minimizeOnScrollFollowsItsSettingAndDefaultsOn() async {
        #expect(await model().minimizesTabBarOnScroll)
        let store = InMemorySettingsStore()
        store.set(false, for: SettingKey.tabBarMinimizesOnScroll)
        #expect(await model(store: store).minimizesTabBarOnScroll == false)
    }

    @Test func plusListsTheSevenLegacyEntriesAndNoneIsADeadRow() {
        #expect(PlusEntry.allCases.map(\.title) == [
            "Réglages", "Rechercher sur le forum", "Bookmarks", "Alertes Qualitay", "Crédits", "Charte du forum", "Supprimer mon compte"
        ])
        // Every entry that is not built names the lot that brings it, so its placeholder says what is missing.
        #expect(PlusEntry.allCases.filter { !$0.isBuilt }.allSatisfy { $0.owningLot != nil })
        #expect(PlusEntry.settings.isBuilt)
    }

    @Test func theIPadSidebarFollowsTheLegacySections() {
        #expect(SidebarDestination.sections.map { $0.map(\.title) } == [
            ["Catégories", "Favoris", "Messages"],
            ["Bookmarks", "Alertes Qualitay"],
            ["Réglages", "Rechercher sur le forum", "Crédits", "Charte du forum", "Supprimer mon compte"]
        ])
    }

    @Test func theCategoriesTabStartsWithoutASourceAndFavouritesOnTheFavourites() async {
        let root = await model()
        #expect(root.categories.selectedSource == nil)
        #expect(root.favorites.selectedSource == .favorites)
        #expect(RootModel.favoritesSources == [.favorites, .flagged])
    }
}
