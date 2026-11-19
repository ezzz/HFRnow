import HFRModels
import SwiftUI

// Port of HFRswift/Swift/MainWindow.swift (RootTabView, tab bar branch) @ 2440d79. Differences: the reader opens inside the tab's split;
// a Favoris / Drapeaux source menu (GAP-032; UXD). The reader hides the tab bar only while the split is collapsed
// (GAP-008, UXD-02, see `TopicReaderView`). On a large iPhone in landscape the splits collapse to a stack, as legacy's tab root
// (`TabSplitWidth`, UXD-24, #431).
// LOT-185: the options menu symbol is `ellipsis`, not `ellipsis.circle`; GAP row pending #545.
/// The iPhone root: a tab bar Catégories / Favoris / Messages / Plus, with Recherche before Plus behind an experimental option.
/// Each tab keeps its own navigation, and the reader opens inside the tab (a collapsed split view is a stack).
struct RootTabsView: View {
    @Bindable var model: RootModel
    let environment: AppEnvironment
    @Environment(ExperimentalSettings.self) private var experimental: ExperimentalSettings?

    var body: some View {
        let hasSearchTab = SearchTabOption.isOn(experimental)
        TabView(selection: Binding(
            get: { SearchTabOption.visibleTab(model.selectedTab, isOn: hasSearchTab) }, set: { model.selectedTab = $0 }
        )) {
            Tab(RootTab.categories.title, systemImage: RootTab.categories.symbol, value: RootTab.categories) {
                CategoriesTabView(navigation: model.categories, reader: environment.reader, composer: environment.composer)
                    .environment(\.isSelectedRootTab, model.selectedTab == .categories)
            }
            Tab(RootTab.favorites.title, systemImage: RootTab.favorites.symbol, value: RootTab.favorites) {
                FavoritesTabView(navigation: model.favorites, reader: environment.reader, composer: environment.composer)
                    .environment(\.isSelectedRootTab, model.selectedTab == .favorites)
            }
            Tab(RootTab.messages.title, systemImage: RootTab.messages.symbol, value: RootTab.messages) {
                MessagesRootView(model: model.messages, reader: environment.reader, composer: environment.composer)
                    .environment(\.isSelectedRootTab, model.selectedTab == .messages)
            }
            .badge(model.unreadPrivateMessages)
            // EXPERIMENTAL(searchTab, #896): the fifth item, left of Plus.
            if hasSearchTab {
                Tab(RootTab.search.title, systemImage: RootTab.search.symbol, value: RootTab.search) {
                    SearchRootTab(model: model, environment: environment)
                }
            }
            Tab(RootTab.more.title, systemImage: RootTab.more.symbol, value: RootTab.more) {
                ThemedNavigationStack {
                    PlusView(model: model)
                        .navigationDestination(item: $model.plusEntry) {
                            PlusEntryView(entry: $0, model: model, environment: environment).appScreenBackground()
                        }
                }
                .environment(\.isSelectedRootTab, model.selectedTab == .more)
            }
            .badge(model.plusBadge)
        }
        .tabBarMinimizeBehavior(model.minimizesTabBarOnScroll ? .onScrollDown : .never)
        // EXPERIMENTAL(searchTab, #896): the selection follows the option and the Plus search entry.
        .onChange(of: model.selectedDestination, initial: true) { model.settleSearchTab(isOn: hasSearchTab) }
        .onChange(of: hasSearchTab) { model.settleSearchTab(isOn: hasSearchTab) }
    }
}

/// Catégories: the category list (no flags or favourites on top), its topics, then the reader.
struct CategoriesTabView: View {
    @Bindable var navigation: NavigationModel
    let reader: ReaderServices
    let composer: ComposerServices?
    @State private var column: NavigationSplitViewColumn

    /// `column` is the column a collapsed split shows first (the sidebar; a test starts on another).
    init(navigation: NavigationModel, reader: ReaderServices, composer: ComposerServices?, column: NavigationSplitViewColumn = .sidebar) {
        self.navigation = navigation
        self.reader = reader
        self.composer = composer
        _column = State(initialValue: column)
    }

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $column) {
            ForumListView(navigation: navigation).accountMenuToolbarItem().appScreenBackground()
        } content: {
            TopicsColumn(navigation: navigation, composer: composer, showsAccountMenu: true).appScreenBackground()
        } detail: {
            ReaderColumn(navigation: navigation, reader: reader, composer: composer).appScreenBackground()
        }
        .modifier(TabSplitWidth())
        .filteredPosts(navigation.filtering, reader: reader)
    }
}

/// Favoris: the favourites (or the flags) and the reader.
struct FavoritesTabView: View {
    @Bindable var navigation: NavigationModel
    let reader: ReaderServices
    let composer: ComposerServices?
    @State private var column = NavigationSplitViewColumn.sidebar

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $column) {
            TopicsColumn(navigation: navigation, composer: composer)
                .accountMenuToolbarItem()
                .toolbar { ToolbarItem(placement: .primaryAction) { FavoritesSourceMenu(navigation: navigation) } }
                .appScreenBackground()
        } detail: {
            ReaderColumn(navigation: navigation, reader: reader, composer: composer).appScreenBackground()
        }
        .modifier(TabSplitWidth())
        .filteredPosts(navigation.filtering, reader: reader)
    }
}

/// The Favoris tab's menu: which list it shows (legacy lists both there, setting `AppSettingsView.swift:130-131`) and the
/// favourites options of LOT-124, so they are reachable from the screen and not only from Réglages.
struct FavoritesSourceMenu: View {
    @Bindable var navigation: NavigationModel

    var body: some View {
        Menu("Options", systemImage: "ellipsis") {
            Picker("Liste", selection: $navigation.selectedSource) {
                ForEach(RootModel.favoritesSources, id: \.self) { source in
                    Text(source.title).tag(Optional(source))
                }
            }
            if let options = navigation.favorites { FavoritesOptionsMenuItems(navigation: navigation, options: options) }
        }
    }
}

/// The favourites options as menu items: sort, folded sections, automatic refresh, fold all / unfold all.
private struct FavoritesOptionsMenuItems: View {
    let navigation: NavigationModel
    @Bindable var options: FavoritesOptionsModel

    private var page: FavoritesPage? {
        navigation.selectedSource.flatMap { navigation.topicList(for: $0).loader.value?.favoritesPage }
    }

    var body: some View {
        Section {
            Toggle("Trier par catégorie", isOn: $options.groupedByCategory)
            Toggle("Afficher les sections repliées", isOn: $options.showsCollapsedSections)
            Toggle("Actualisation automatique des favoris", isOn: $options.autoRefresh)
        }
        Section {
            Button("Tout replier", systemImage: "rectangle.compress.vertical") {
                if let page { Task { await options.collapseAll(in: page) } }
            }
            .disabled(page.map { !options.canCollapseMore(in: $0) } ?? true)
            Button("Tout déplier", systemImage: "rectangle.expand.vertical") { Task { await options.expandAll() } }
                .disabled(!options.groupedByCategory || options.collapsedSections.isEmpty)
        }
    }
}

/// The topics of the chosen source.
struct TopicsColumn: View {
    @Bindable var navigation: NavigationModel
    /// The current account's composer (LOT-089); nil when logged out.
    let composer: ComposerServices?
    /// Favoris: what a section title does. Nil pushes the category on this column's stack (compact width, as legacy's
    /// `NavigationLink`); the regular-width iPad sidebar passes the switch to Catégories (`onOpenForum`, `MainWindow.swift:2221-2232`).
    var openCategory: ((TopicSource) -> Void)?
    /// A column that is a pushed screen (a category's topics) shows the account button after its back button (#425).
    var showsAccountMenu = false
    /// `TabSplitWidth` keeps `.regular` on a foldable's inner screen: all three columns show and the category list already has the
    /// button, so a second one beside it would double it (legacy carries it on its list column only, `MainWindow.swift:1932-1938`
    /// @ 87fe0d1c). Not tested at that width: the foldable check is on #893.
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    var body: some View {
        if let source = navigation.selectedSource {
            TopicListView(
                model: navigation.topicList(for: source), selection: $navigation.selectedTopic, filtering: navigation.filtering,
                composer: composer, open: { navigation.open($0, at: $1) }, scope: navigation.scope(for: source),
                openCategory: navigation.favorites == nil ? nil : (openCategory ?? { navigation.openCategory($0) }),
                // Favoris is a main screen with its large title; the lists a forum row pushes get the pill (#977, #978).
                titleStyle: .topicList(isFavoritesRoot: navigation.favorites != nil),
                showsAccountMenu: showsAccountMenu && horizontalSizeClass != .regular
            )
            .id(source)
            .navigationDestination(item: $navigation.openedCategory) { category in
                TopicListView(
                    model: navigation.topicList(for: category), selection: $navigation.selectedTopic, filtering: navigation.filtering,
                    composer: composer, open: { navigation.open($0, at: $1) }, scope: navigation.scope(for: category),
                    showsAccountMenu: true
                )
                .appScreenBackground()
            }
        } else {
            ContentUnavailableView("Choisissez un forum", systemImage: "list.bullet")
        }
    }
}

/// The reader of the chosen topic.
struct ReaderColumn: View {
    let navigation: NavigationModel
    let reader: ReaderServices
    /// The reply composer (LOT-084); nil when logged out, which hides "Répondre".
    let composer: ComposerServices?

    var body: some View {
        if let topic = navigation.selectedTopic, let model = navigation.reader(for: topic) {
            // Its own stack, for the readers a followed link pushes (LOT-137); a new topic starts a new stack.
            ThemedNavigationStack {
                TopicReaderView(
                    model: model, services: reader, composer: composer,
                    onFilterPosts: topic.topicID == nil ? nil : { navigation.filtering.start(opening: topic) },
                    filterIsBusy: navigation.filtering.isBusy
                )
            }
            // A row menu's page (LOT-125) is a new reader even for the topic on screen.
            .id("\(topic.id)#\(navigation.readerGeneration)")
        } else {
            MessagePlaceholderView(topic: navigation.selectedTopic)
        }
    }
}
