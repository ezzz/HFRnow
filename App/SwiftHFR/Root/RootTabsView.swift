import HFRModels
import SwiftUI

// Port of HFRswift/Swift/MainWindow.swift (RootTabView, tab bar branch) @ 2440d79. Differences: the reader opens inside the tab's split;
// a Favoris / Drapeaux source menu (GAP-032; UXD). The reader hides the tab bar (GAP-008, UXD-02, see `TopicReaderView`).
/// The iPhone root: a tab bar Catégories / Favoris / Messages / Plus. Each tab keeps its own navigation, and the reader
/// opens inside the tab (a collapsed split view is a stack).
struct RootTabsView: View {
    @Bindable var model: RootModel
    let environment: AppEnvironment

    var body: some View {
        TabView(selection: $model.selectedTab) {
            Tab(RootTab.categories.title, systemImage: RootTab.categories.symbol, value: RootTab.categories) {
                CategoriesTabView(navigation: model.categories, reader: environment.reader, composer: environment.composer)
            }
            Tab(RootTab.favorites.title, systemImage: RootTab.favorites.symbol, value: RootTab.favorites) {
                FavoritesTabView(navigation: model.favorites, reader: environment.reader, composer: environment.composer)
            }
            Tab(RootTab.messages.title, systemImage: RootTab.messages.symbol, value: RootTab.messages) {
                MessagesRootView(model: model.messages, environment: environment)
            }
            .badge(model.unreadPrivateMessages)
            Tab(RootTab.more.title, systemImage: RootTab.more.symbol, value: RootTab.more) {
                NavigationStack {
                    PlusView(model: model)
                        .navigationDestination(item: $model.plusEntry) { PlusEntryView(entry: $0, model: model, environment: environment) }
                }
            }
        }
        .tabBarMinimizeBehavior(model.minimizesTabBarOnScroll ? .onScrollDown : .never)
    }
}

/// Catégories: the category list (no flags or favourites on top), its topics, then the reader.
struct CategoriesTabView: View {
    @Bindable var navigation: NavigationModel
    let reader: ReaderServices
    let composer: ComposerServices?
    @State private var column = NavigationSplitViewColumn.sidebar

    var body: some View {
        NavigationSplitView(preferredCompactColumn: $column) {
            ForumListView(navigation: navigation)
        } content: {
            TopicsColumn(navigation: navigation, composer: composer)
        } detail: {
            ReaderColumn(navigation: navigation, reader: reader, composer: composer)
        }
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
                .toolbar { ToolbarItem(placement: .primaryAction) { FavoritesSourceMenu(navigation: navigation) } }
        } detail: {
            ReaderColumn(navigation: navigation, reader: reader, composer: composer)
        }
        .filteredPosts(navigation.filtering, reader: reader)
    }
}

/// The Favoris tab's menu: which list it shows (legacy lists both there, setting `AppSettingsView.swift:130-131`) and the
/// favourites options of LOT-124, so they are reachable from the screen and not only from Réglages.
struct FavoritesSourceMenu: View {
    @Bindable var navigation: NavigationModel

    var body: some View {
        Menu("Options", systemImage: "ellipsis.circle") {
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

    var body: some View {
        if let source = navigation.selectedSource {
            TopicListView(model: navigation.topicList(for: source), selection: $navigation.selectedTopic, filtering: navigation.filtering,
                          composer: composer)
                .id(source)
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
            NavigationStack {
                TopicReaderView(
                    model: model, services: reader, composer: composer,
                    onFilterPosts: topic.topicID == nil ? nil : { navigation.filtering.start(opening: topic) },
                    filterIsBusy: navigation.filtering.isBusy
                )
            }
            .id(topic.id)
        } else {
            MessagePlaceholderView(topic: navigation.selectedTopic)
        }
    }
}
