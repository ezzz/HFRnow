import SwiftUI

/// The regular-width iPad root: the legacy sidebar (lists, tools, Plus entries), with the topic list and the reader beside it.
struct RootSidebarView: View {
    @Bindable var model: RootModel
    let environment: AppEnvironment
    /// All columns at launch and not persisted: an intentional difference (legacy defaults to two columns and persists the
    /// choice, `MainWindow.swift:1351`, `:1434-1505`).
    @State private var visibility = NavigationSplitViewVisibility.all
    @State private var compactColumn = NavigationSplitViewColumn.sidebar

    var body: some View {
        if case .plus(let entry) = model.sidebarDestination {
            // Legacy: the Plus entries have no list, so a two-column split with the entry in a stack in the detail column
            // (`MainWindow.swift:1305-1311`, `:1744-1755`, `:1876-1891`).
            NavigationSplitView(columnVisibility: $visibility, preferredCompactColumn: $compactColumn) {
                sidebar
            } detail: {
                // A new identity per entry, so the stack drops what the previous entry had pushed.
                NavigationStack { PlusEntryView(entry: entry) }
                    .id(entry)
            }
        } else {
            NavigationSplitView(columnVisibility: $visibility) {
                sidebar
            } content: {
                content
            } detail: {
                detail
            }
        }
    }

    private var sidebar: some View {
        List(selection: selection) {
            ForEach(Array(SidebarDestination.sections.enumerated()), id: \.offset) { _, section in
                Section {
                    ForEach(section, id: \.self) { destination in
                        Label(destination.title, systemImage: destination.symbol)
                            .foregroundStyle(destination == .plus(.deleteAccount) ? Color.red : Color.primary)
                            .badge(destination == .tab(.messages) ? model.unreadPrivateMessages : 0)
                            .tag(destination)
                    }
                }
            }
        }
        .navigationTitle("HFR")
        .toolbar { ToolbarItem(placement: .primaryAction) { AccountMenuButton() } }
    }

    /// A sidebar list selects an optional; deselecting keeps the current destination.
    private var selection: Binding<SidebarDestination?> {
        Binding(get: { model.sidebarDestination }, set: { if let new = $0 { model.selectedDestination = new } })
    }

    @ViewBuilder
    private var content: some View {
        switch model.sidebarDestination {
        case .tab(.categories):
            CategoriesSidebarColumn(navigation: model.categories)
        case .tab(.favorites):
            TopicsColumn(navigation: model.favorites)
                .toolbar { ToolbarItem(placement: .secondaryAction) { FavoritesSourceMenu(navigation: model.favorites) } }
        case .tab(.messages):
            MessagesListColumn(model: model.messages)
        case .tab(.more), .plus:
            // Unreachable: `sidebarDestination` maps Plus to Réglages, and a Plus entry takes the two-column split above.
            EmptyView()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.sidebarDestination {
        case .tab(.categories): ReaderColumn(navigation: model.categories, reader: environment.reader, composer: environment.composer)
        case .tab(.favorites): ReaderColumn(navigation: model.favorites, reader: environment.reader, composer: environment.composer)
        case .tab(.messages): MessageReaderColumn(model: model.messages, reader: environment.reader, composer: environment.composer)
        default: ContentUnavailableView("Choisissez un élément", systemImage: "sidebar.left")
        }
    }
}

/// The category list opening its topics in the same column, so the reader keeps the detail column.
private struct CategoriesSidebarColumn: View {
    @Bindable var navigation: NavigationModel

    var body: some View {
        NavigationStack {
            ForumListView(navigation: navigation)
                .navigationDestination(item: $navigation.selectedSource) { source in
                    TopicListView(model: navigation.topicList(for: source), selection: $navigation.selectedTopic)
                }
        }
    }
}
