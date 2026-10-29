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
    /// The one selection both layouts read, so a size-class change (Slide Over, Split View) keeps what the user was on.
    var selectedDestination: SidebarDestination

    /// Tab shown by the iPhone tab bar: a Plus entry selected in the sidebar is the Plus tab. Setting it selects that tab,
    /// except that re-selecting Plus keeps the entry the sidebar had open.
    var selectedTab: RootTab {
        get {
            switch selectedDestination {
            case .tab(let tab): tab
            case .plus: .more
            }
        }
        set {
            guard newValue != selectedTab else { return }
            selectedDestination = .tab(newValue)
        }
    }

    @ObservationIgnored private let store: any SettingsStore

    /// Creates the root state; the start tab is read once from the start-screen setting (`HFRswiftStartupScreen`).
    init(forums: ForumListModel, categories: NavigationModel, favorites: NavigationModel, store: any SettingsStore) {
        self.forums = forums
        self.categories = categories
        self.favorites = favorites
        self.store = store
        selectedDestination = .tab(RootTab(startup: store.value(for: SettingKey.startupScreen)))
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
