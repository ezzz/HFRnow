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
    /// The private message list and the open conversation of the Messages tab (LOT-126), shared by the tab bar and the
    /// sidebar so a size-class change keeps the page and the conversation on screen.
    let messages: MessageListModel
    /// The one selection both layouts read, so a size-class change (Slide Over, Split View) keeps what the user was on.
    var selectedDestination: SidebarDestination {
        didSet {
            if case .plus(let entry) = selectedDestination { lastPlusEntry = entry }
        }
    }
    /// The Plus entry left open when the user switched to another tab: coming back to Plus reopens it, as every other tab
    /// keeps its stack.
    @ObservationIgnored private var lastPlusEntry: PlusEntry?

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
            selectedDestination = newValue == .more ? lastPlusEntry.map(SidebarDestination.plus) ?? .tab(.more) : .tab(newValue)
        }
    }

    /// The Plus entry the Plus tab shows on top of its menu, derived from the one selection: an entry opened in the
    /// sidebar is still open when Slide Over or Split View switches to the tab bar, and Back returns to the Plus menu. An
    /// optional item, not a typed path, so the entry's own pushes (Réglages > Icône, Thème) stay in the stack's path.
    var plusEntry: PlusEntry? {
        get {
            if case .plus(let entry) = selectedDestination { entry } else { nil }
        }
        set {
            guard selectedTab == .more else { return }
            if newValue == nil { lastPlusEntry = nil }
            selectedDestination = newValue.map(SidebarDestination.plus) ?? .tab(.more)
        }
    }

    /// The destination the iPad sidebar shows: the Plus tab has no list there, it opens Réglages (legacy
    /// `defaultIPadDestination`, `MainWindow.swift:1365-1376`).
    var sidebarDestination: SidebarDestination {
        selectedDestination == .tab(.more) ? .plus(.settings) : selectedDestination
    }

    /// Whether the Messages badge is shown (`mp_badge_enabled`, legacy default on); refreshed by `reloadSettings()`.
    private(set) var privateMessageBadgeEnabled: Bool
    /// Whether the tab bar shrinks while a list scrolls (`tabbar_minimize_on_scroll`, legacy default on); refreshed by
    /// `reloadSettings()`.
    private(set) var minimizesTabBarOnScroll: Bool

    @ObservationIgnored private let store: any SettingsStore

    /// Creates the root state. `initial` is what the user was on before a rebuild (a new session generation); only the first
    /// creation (nil) reads the start tab from the start-screen setting (`HFRswiftStartupScreen`), as legacy keeps the tab
    /// it was on (`MainWindow.swift:1276-1278`, `:1357-1362`).
    init(
        forums: ForumListModel, categories: NavigationModel, favorites: NavigationModel, messages: MessageListModel,
        store: any SettingsStore, initial: SidebarDestination? = nil
    ) {
        self.forums = forums
        self.categories = categories
        self.favorites = favorites
        self.messages = messages
        self.store = store
        let destination = initial ?? .tab(RootTab(startup: store.value(for: SettingKey.startupScreen)))
        selectedDestination = destination
        // The init accessor skips `didSet`: a rebuilt root on a Plus entry records it here (from the local, as reading the
        // observed property would use `self` before every stored property is set).
        if case .plus(let entry) = destination { lastPlusEntry = entry }
        privateMessageBadgeEnabled = store.value(for: SettingKey.privateMessageBadge)
        minimizesTabBarOnScroll = store.value(for: SettingKey.tabBarMinimizesOnScroll)
    }

    /// The source each tab opens on: Catégories none (the user picks a forum), Favoris the favourites.
    static let categoriesStartupSource: TopicSource? = nil
    static let favoritesStartupSource: TopicSource? = .favorites

    /// Builds the models over the engine objects of one session.
    convenience init(environment: AppEnvironment, store: any SettingsStore, initial: SidebarDestination? = nil) {
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
        self.init(
            forums: forums, categories: navigation(startup: Self.categoriesStartupSource),
            favorites: navigation(startup: Self.favoritesStartupSource), messages: environment.makeMessageList(),
            store: store, initial: initial
        )
    }

    /// Unread private messages for the Messages badge: 0 hides it, and so does the badge setting (`mp_badge_enabled`, legacy
    /// `MainWindow.swift:1349`). Logged out, the home page gives no count.
    var unreadPrivateMessages: Int {
        guard privateMessageBadgeEnabled else { return 0 }
        return max(forums.loader.value?.unreadPrivateMessages ?? 0, 0)
    }

    /// Reads the badge and minimize settings again, so a change made in Réglages shows without a relaunch. The legacy app-icon
    /// badge (`MainWindow.swift:1509-1512`) is out of scope.
    func reloadSettings() {
        let badge = store.value(for: SettingKey.privateMessageBadge)
        let minimize = store.value(for: SettingKey.tabBarMinimizesOnScroll)
        if badge != privateMessageBadgeEnabled { privateMessageBadgeEnabled = badge }
        if minimize != minimizesTabBarOnScroll { minimizesTabBarOnScroll = minimize }
    }

    /// Sources the Favoris tab can show: the favourites and, where legacy shows them with the favourites, the flags.
    static let favoritesSources: [TopicSource] = [.favorites, .flagged]
}
