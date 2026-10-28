import SwiftUI

/// The regular-width iPad root: the legacy sidebar (lists, tools, Plus entries), with the topic list and the reader beside it.
struct RootSidebarView: View {
    @Bindable var model: RootModel
    let reader: ReaderServices
    /// All columns at launch, as legacy (`MainWindow.swift` iPad split visibility), so the sidebar is not hidden.
    @State private var visibility = NavigationSplitViewVisibility.all

    var body: some View {
        NavigationSplitView(columnVisibility: $visibility) {
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
        } content: {
            content
        } detail: {
            detail
        }
    }

    /// A sidebar list selects an optional; deselecting keeps the current destination.
    private var selection: Binding<SidebarDestination?> {
        Binding(get: { model.selectedDestination }, set: { if let new = $0 { model.selectedDestination = new } })
    }

    @ViewBuilder
    private var content: some View {
        switch model.selectedDestination {
        case .tab(.categories):
            CategoriesSidebarColumn(navigation: model.categories)
        case .tab(.favorites):
            TopicsColumn(navigation: model.favorites)
                .toolbar { ToolbarItem(placement: .secondaryAction) { FavoritesSourceMenu(navigation: model.favorites) } }
        case .tab(.messages):
            NavigationStack { MessagesRootView() }
        case .tab(.more):
            PlusView()
        case .plus(let entry):
            PlusEntryView(entry: entry)
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.selectedDestination {
        case .tab(.categories): ReaderColumn(navigation: model.categories, reader: reader)
        case .tab(.favorites): ReaderColumn(navigation: model.favorites, reader: reader)
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
