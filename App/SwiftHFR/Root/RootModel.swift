import HFRModels
import HFRStorage
import Observation

/// State shared by the root navigation, whether it is the iPhone tab bar or the iPad sidebar: the selected tab or
/// destination, the unread private-message badge and the tab-bar setting (LOT-170).
@MainActor
@Observable
final class RootModel {
    /// The forum list, loaded at launch whatever the start tab: the home page carries the unread private-message count.
    let forums: ForumListModel
    /// Selection and models of the Catégories tab: forum list, then topics, then the reader.
    let categories: NavigationModel
    /// Selection and models of the Favoris tab. Its source is the favourites, or the flags the user switches to.
    let favorites: NavigationModel
    /// Tab shown by the iPhone tab bar.
    var selectedTab: RootTab
    /// Destination shown by the iPad sidebar.
    var selectedDestination: SidebarDestination

    @ObservationIgnored private let store: any SettingsStore

    /// Creates the root state; the start tab is read once from the start-screen setting (`HFRswiftStartupScreen`).
    init(forums: ForumListModel, categories: NavigationModel, favorites: NavigationModel, store: any SettingsStore) {
        self.forums = forums
        self.categories = categories
        self.favorites = favorites
        self.store = store
        let start = RootTab(startup: store.value(for: SettingKey.startupScreen))
        selectedTab = start
        selectedDestination = .tab(start)
    }

    /// Builds the models over the engine objects of one session.
    convenience init(environment: AppEnvironment, store: any SettingsStore) {
        let forums = ForumListModel(
            dataSource: environment.dataSource, visibility: environment.visibility, accountName: environment.accountName
        )
        func navigation(startup: TopicSource?) -> NavigationModel {
            NavigationModel(
                dataSource: environment.dataSource, forums: forums, sessionIsLoggedIn: environment.isLoggedIn,
                topicPages: environment.topicPages, renderOptions: environment.reader.settings.renderOptions,
                startupSource: startup
            )
        }
        self.init(forums: forums, categories: navigation(startup: nil), favorites: navigation(startup: .favorites), store: store)
    }

    /// Unread private messages for the Messages badge: 0 hides it, and so does the badge setting (`mp_badge_enabled`, legacy
    /// `MainWindow.swift:1349`). Logged out, the home page gives no count.
    var unreadPrivateMessages: Int {
        guard store.value(for: SettingKey.privateMessageBadge) else { return 0 }
        return max(forums.loader.value?.unreadPrivateMessages ?? 0, 0)
    }

    /// Whether the tab bar shrinks while a list scrolls (`tabbar_minimize_on_scroll`, legacy default on).
    var minimizesTabBarOnScroll: Bool { store.value(for: SettingKey.tabBarMinimizesOnScroll) }

    /// Sources the Favoris tab can show: the favourites and, where legacy shows them with the favourites, the flags.
    static let favoritesSources: [TopicSource] = [.favorites, .flagged]
}
