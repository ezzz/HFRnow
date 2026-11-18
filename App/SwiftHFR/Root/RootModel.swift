import HFRModels
import HFRStorage
import Observation

// Port of HFRswift/Swift/MainWindow.swift (RootTabView: selectedTab, mp_badge_enabled, tabbar_minimize_on_scroll) @ 2440d79.
// Differences: the MP badge comes from `PrivateMessageCount` (GAP-004, #762); the start tab is a setting
// taken from master (GAP-002, UXD).
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
    /// The favourites options the Favoris tab shares with its lists (LOT-124); nil in tests that do not need them.
    let favoriteOptions: FavoritesOptionsModel?
    /// The forum search form and results (LOT-115), shared by the tab bar and the sidebar so a size-class change keeps them.
    let search: ForumSearchModel
    /// MPStorage sync of the current account (LOT-130), shared by the Messages list (flags) and Réglages; nil logged out.
    let mpStorage: MPStorageSyncModel?
    /// The current account's blocklist kept in step with its MPStorage document (LOT-131); nil logged out.
    let blocklistSync: BlocklistSyncModel?
    /// The unread private messages count the list pages of this session announced, newest first (#762).
    let privateMessageCount: PrivateMessageCount
    /// Bookmarks and Alertes Qualitay on the regular-width iPad: the reader of the topic a row opened, shown in the detail column
    /// beside the list, one per entry so each keeps its own (legacy `bookmarksTopicTarget`, `qualityAlertsTopicTarget`,
    /// `selectTopic(_:for:)`, `MainWindow.swift:2195-2213` @ 87fe0d1c, #685).
    private(set) var detailReaders: [PlusEntry: TopicReaderModel] = [:]
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
        switch selectedDestination {
        case .tab(.more): .plus(.settings)
        // EXPERIMENTAL(searchTab, #896): the sidebar has no fifth tab; its search entry is the Plus one.
        case .tab(.search): .plus(.search)
        default: selectedDestination
        }
    }

    /// EXPERIMENTAL(searchTab, #896): keeps the selection coherent with the tab bar. With the Recherche tab, the Plus search entry
    /// is that tab (one live search screen on the shared model, not two); without it, a selected Recherche tab is Plus.
    func settleSearchTab(isOn: Bool) {
        if isOn, selectedDestination == .plus(.search) {
            // Forget the entry too: Plus would otherwise reopen it and be sent back to Recherche, never showing its menu.
            lastPlusEntry = nil
            selectedDestination = .tab(.search)
        } else if !isOn, selectedDestination == .tab(.search) {
            selectedDestination = .tab(.more)
        }
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
        search: ForumSearchModel = ForumSearchModel(source: UnavailableForumSearch()),
        store: any SettingsStore, initial: SidebarDestination? = nil, favoriteOptions: FavoritesOptionsModel? = nil,
        mpStorage: MPStorageSyncModel? = nil, privateMessageCount: PrivateMessageCount = PrivateMessageCount(),
        blocklistSync: BlocklistSyncModel? = nil
    ) {
        self.mpStorage = mpStorage
        self.blocklistSync = blocklistSync
        self.privateMessageCount = privateMessageCount
        self.favoriteOptions = favoriteOptions
        self.forums = forums
        self.categories = categories
        self.favorites = favorites
        self.messages = messages
        self.search = search
        self.store = store
        let destination = initial ?? .tab(RootTab(startup: store.value(for: SettingKey.startupScreen)))
        selectedDestination = destination
        // The init accessor skips `didSet`: a rebuilt root on a Plus entry records it here (from the local, as reading the
        // observed property would use `self` before every stored property is set).
        if case .plus(let entry) = destination { lastPlusEntry = entry }
        privateMessageBadgeEnabled = store.value(for: SettingKey.privateMessageBadge)
        minimizesTabBarOnScroll = store.value(for: SettingKey.tabBarMinimizesOnScroll)
    }

    /// The source each tab opens on: Catégories none (the user picks a forum), Favoris the favourites. The environment-built
    /// Favoris tab opens on the list its favourites mode names instead (`TopicSource(mode:)`, LOT-124); this is the fallback of
    /// a model built without options.
    static let categoriesStartupSource: TopicSource? = nil
    static let favoritesStartupSource: TopicSource? = .flagged

    /// The Messages model over this session; the reader opens a conversation with the same page source. Private on purpose:
    /// the tab and the sidebar must take `messages`, never build a second model that would lose the open conversation.
    private static func messageList(
        _ environment: AppEnvironment, store: any SettingsStore, mpStorage: MPStorageSyncModel?, count: PrivateMessageCount
    ) -> MessageListModel {
        MessageListModel(
            source: environment.privateMessages, isLoggedIn: environment.isLoggedIn, topicPages: environment.topicPages,
            renderOptions: environment.reader.settings.renderOptions, settings: store, mpStorage: mpStorage,
            privateMessageCount: count,
            // What the list shows is not notified by the next background check (LOT-140).
            ledgerSeen: environment.currentAccountName.map { account in
                { @Sendable (summary: NotificationSummary) async in
                    await MPNotificationLedger.recordSeen(summary, account: account)
                }
            }
        )
    }

    /// Builds the models over the engine objects of one session.
    convenience init(environment: AppEnvironment, store: any SettingsStore, initial: SidebarDestination? = nil) {
        // Every list the tabs load goes through this source, so the badge takes HFR's count from whichever page came last. The
        // count is the session's, shared by every window (LOT-146).
        let count = environment.privateMessageCount ?? PrivateMessageCount()
        let dataSource = PrivateMessageCountingSource(
            base: environment.dataSource, count: count,
            countSeen: environment.currentAccountName.map { account in
                { @Sendable (seen: Int) async in
                    await MPNotificationLedger.recordSeen(NotificationSummary(unreadPrivateMessages: seen), account: account)
                }
            }
        )
        let forums = ForumListModel(
            dataSource: dataSource, visibility: environment.visibility, accountName: environment.accountName
        )
        let options = FavoritesOptionsModel(settings: store, stores: environment.favoriteStores)
        // One choice for both tabs: a category opened from a Favoris heading sets it, the Catégories lists read it.
        let topicFilter = TopicFilterModel(settings: store)
        // One per account session: a new account rebuilds the root, so no account's MPStorage state shows under another.
        let mpStorage = environment.currentAccountName.map {
            MPStorageSyncModel.live(account: $0, session: environment.session, settings: store)
        }
        func navigation(
            startup: TopicSource?, favorites: FavoritesOptionsModel? = nil, topicFilter: TopicFilterModel? = nil
        ) -> NavigationModel {
            NavigationModel(
                dataSource: dataSource, forums: forums, sessionIsLoggedIn: environment.isLoggedIn,
                topicPages: environment.topicPages, renderOptions: environment.reader.settings.renderOptions,
                filteredPosts: environment.filteredPosts, startupSource: startup, favorites: favorites,
                flagActions: environment.flagActions, topicFilter: topicFilter
            )
        }
        // The Favoris tab opens on the list the favourites mode names (legacy default: "Drapeaux & Favoris").
        self.init(
            forums: forums, categories: navigation(startup: Self.categoriesStartupSource, topicFilter: topicFilter),
            favorites: navigation(startup: TopicSource(mode: options.mode), favorites: options, topicFilter: topicFilter),
            messages: Self.messageList(environment, store: store, mpStorage: mpStorage, count: count),
            search: ForumSearchModel(
                source: LiveForumSearchSource(session: environment.session), topicPages: environment.topicPages,
                renderOptions: environment.reader.settings.renderOptions, store: store
            ),
            store: store, initial: initial, favoriteOptions: options, mpStorage: mpStorage, privateMessageCount: count,
            blocklistSync: Self.blocklistSync(environment, mpStorage: mpStorage)
        )
    }

    /// The blocklist sync of the session's account (LOT-131): over the app's one list store, refreshing the reader's copy.
    private static func blocklistSync(_ environment: AppEnvironment, mpStorage: MPStorageSyncModel?) -> BlocklistSyncModel? {
        guard let mpStorage, let changes = environment.blocklistChanges else { return nil }
        let snapshot = environment.pseudoListsSnapshot
        return BlocklistSyncModel(
            mpStorage: mpStorage, store: PseudoListsSnapshot.liveStore, changes: changes, refreshLists: { await snapshot.refresh() }
        )
    }

    /// Unread private messages for the Messages badge: 0 hides it, and so does the badge setting (`mp_badge_enabled`, legacy
    /// `MainWindow.swift:1349`). The count is the newest one a list page announced, not only the launch's home page (#762);
    /// logged out, no page gives one.
    var unreadPrivateMessages: Int {
        guard privateMessageBadgeEnabled else { return 0 }
        return max(privateMessageCount.latest ?? 0, 0)
    }

    /// Regular-width iPad: shows `reader` in the detail column of `entry`, a topic-list Plus entry, in place of what it showed (a
    /// new stack: what a link had pushed there goes). Another entry is ignored: it has no detail column for a topic.
    func openInDetail(_ reader: TopicReaderModel, for entry: PlusEntry) {
        guard entry.usesTopicList else { return }
        detailReaders[entry]?.closeLinkedReaders()
        detailReaders[entry] = reader
    }

    /// Empties `entry`'s detail column: legacy's placeholder shows again (a deleted bookmark, `MainWindow.swift:2266-2271`).
    func closeDetail(for entry: PlusEntry) {
        detailReaders[entry]?.closeLinkedReaders()
        detailReaders[entry] = nil
    }

    /// Regular-width iPad: a Favoris section title switches the content column to Catégories on that category, on the Favoris
    /// filter (legacy `showTopicsForForum(_, initialFlagOverride: .favorites)`, `MainWindow.swift:2221-2232` @ 87fe0d1c).
    func showCategoryFromFavorites(_ category: TopicSource) {
        categories.topicFilter?.flag = .favorites
        categories.selectedSource = category
        // Legacy clears the selected topic too. Dropping the selection drops the reader and what its links pushed, even when the
        // category was already open (`NavigationModel.selectedTopic`).
        categories.selectedTopic = nil
        selectedDestination = .tab(.categories)
    }

    /// Reads the badge and minimize settings again, so a change made in Réglages shows without a relaunch. The app icon badge
    /// follows `appIconBadge` (LOT-140).
    func reloadSettings() {
        let badge = store.value(for: SettingKey.privateMessageBadge)
        let minimize = store.value(for: SettingKey.tabBarMinimizesOnScroll)
        if let options = favoriteOptions {
            options.reloadSettings()
            // The mode names the list (legacy reads `vos_sujets` on every load): a change made in Réglages switches the tab.
            if favorites.selectedSource?.favoritesMode != options.mode { favorites.selectedSource = TopicSource(mode: options.mode) }
        }
        if badge != privateMessageBadgeEnabled { privateMessageBadgeEnabled = badge }
        if minimize != minimizesTabBarOnScroll { minimizesTabBarOnScroll = minimize }
    }

    /// Sources the Favoris tab can show: the favourites and, where legacy shows them with the favourites, the flags.
    static let favoritesSources: [TopicSource] = [.favorites, .flagged]
}
