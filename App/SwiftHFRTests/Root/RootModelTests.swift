import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

@MainActor
struct RootModelTests {
    private func model(
        store: InMemorySettingsStore = InMemorySettingsStore(), unread: Int? = 3, loggedIn: Bool = true,
        initial: SidebarDestination? = nil
    ) async -> RootModel {
        let source = FakeDataSource()
        source.forumHandler = { ForumListPage(forums: [], isLoggedIn: loggedIn, unreadPrivateMessages: unread) }
        let forums = ForumListModel(dataSource: source)
        let root = RootModel(
            forums: forums,
            categories: NavigationModel(dataSource: source, forums: forums, startupSource: RootModel.categoriesStartupSource),
            favorites: NavigationModel(dataSource: source, forums: forums, startupSource: RootModel.favoritesStartupSource),
            store: store, initial: initial
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

    // Reverting `selectedTab`'s setter to a stored property (no write to `selectedDestination`) fails this test.
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

    // Removing the `guard privateMessageBadgeEnabled` line of `unreadPrivateMessages` fails this test.
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

    @Test func plusListsTheSevenLegacyEntriesWithTheirSymbols() {
        #expect(PlusEntry.allCases.map(\.title) == [
            "Réglages", "Rechercher sur le forum", "Bookmarks", "Alertes Qualitay", "Crédits", "Charte du forum", "Supprimer mon compte"
        ])
        // Legacy `PlusTab.swift:17-62`, iPad sidebar `MainWindow.swift:2236-2245`.
        #expect(PlusEntry.allCases.map(\.symbol) == [
            "gearshape", "magnifyingglass", "pin", "bell", "info.circle", "doc.text", "trash"
        ])
        #expect(PlusEntry.allCases.filter(\.isDestructive) == [.deleteAccount])
    }

    @Test func onlySettingsIsBuiltAndTheOthersNameTheirLot() {
        let expected: [PlusEntry: String?] = [
            .settings: nil, .search: "LOT-115", .bookmarks: "LOT-132", .qualityAlerts: "LOT-133",
            .credits: "LOT-120", .charter: "LOT-120", .deleteAccount: "LOT-157"
        ]
        for entry in PlusEntry.allCases {
            #expect(entry.owningLot == expected[entry]!)
            #expect(entry.isBuilt == (expected[entry]! == nil))
        }
    }

    @Test func sidebarRowsUseTheLegacySymbols() {
        #expect(SidebarDestination.sections.flatMap { $0.map(\.symbol) } == [
            "folder.fill", "star.fill", "envelope", "pin", "bell", "gearshape", "magnifyingglass", "info.circle", "doc.text", "trash"
        ])
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
        // The environment-built model passes these same two constants to its navigation models.
        #expect(RootModel.categoriesStartupSource == nil)
        #expect(RootModel.favoritesStartupSource == .favorites)
    }

    @Test func settingsChangesShowAfterReloadSettings() async {
        let store = InMemorySettingsStore()
        let root = await model(store: store, unread: 4)
        #expect(root.unreadPrivateMessages == 4)
        #expect(root.minimizesTabBarOnScroll)
        store.set(false, for: SettingKey.privateMessageBadge)
        store.set(false, for: SettingKey.tabBarMinimizesOnScroll)
        // Not yet read: the model holds the values it had.
        #expect(root.unreadPrivateMessages == 4)
        root.reloadSettings()
        #expect(root.unreadPrivateMessages == 0)
        #expect(root.minimizesTabBarOnScroll == false)
        store.set(true, for: SettingKey.privateMessageBadge)
        root.reloadSettings()
        #expect(root.unreadPrivateMessages == 4)
    }

    @Test func aRebuiltRootKeepsTheDestinationAndTheStartSettingAppliesOnlyOnce() async {
        let store = InMemorySettingsStore()
        store.set(StartupScreen.categories, for: SettingKey.startupScreen)
        #expect(await model(store: store).selectedDestination == .tab(.categories))
        #expect(await model(store: store, initial: .tab(.messages)).selectedDestination == .tab(.messages))
        #expect(await model(store: store, initial: .plus(.credits)).selectedTab == .more)
    }

    @Test func theIPadSidebarOpensSettingsForThePlusTab() async {
        let root = await model()
        root.selectedDestination = .tab(.more)
        #expect(root.sidebarDestination == .plus(.settings))
        // The tab bar still shows Plus for that selection.
        #expect(root.selectedTab == .more)
        root.selectedDestination = .plus(.search)
        #expect(root.sidebarDestination == .plus(.search))
        root.selectedDestination = .tab(.messages)
        #expect(root.sidebarDestination == .tab(.messages))
    }
}
