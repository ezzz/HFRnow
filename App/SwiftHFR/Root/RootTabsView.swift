import SwiftUI

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
                        .navigationDestination(item: $model.plusEntry) { PlusEntryView(entry: $0) }
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
            TopicsColumn(navigation: navigation)
        } detail: {
            ReaderColumn(navigation: navigation, reader: reader, composer: composer)
        }
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
            TopicsColumn(navigation: navigation)
                .toolbar { ToolbarItem(placement: .secondaryAction) { FavoritesSourceMenu(navigation: navigation) } }
        } detail: {
            ReaderColumn(navigation: navigation, reader: reader, composer: composer)
        }
    }
}

/// Switches the Favoris tab between the favourites and the flags (legacy lists both there, setting `AppSettingsView.swift:130-131`).
struct FavoritesSourceMenu: View {
    @Bindable var navigation: NavigationModel

    var body: some View {
        Picker("Liste", selection: $navigation.selectedSource) {
            ForEach(RootModel.favoritesSources, id: \.self) { source in
                Text(source.title).tag(Optional(source))
            }
        }
    }
}

/// The topics of the chosen source.
struct TopicsColumn: View {
    @Bindable var navigation: NavigationModel

    var body: some View {
        if let source = navigation.selectedSource {
            TopicListView(model: navigation.topicList(for: source), selection: $navigation.selectedTopic)
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
            TopicReaderView(model: model, services: reader, composer: composer)
                .id(topic.id)
        } else {
            MessagePlaceholderView(topic: navigation.selectedTopic)
        }
    }
}
