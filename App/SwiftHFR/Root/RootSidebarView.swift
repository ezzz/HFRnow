import SwiftUI

// Port of HFRswift/Swift/MainWindow.swift (RootTabView.iPadSidebarRoot) @ 2440d79. Differences: sectioned sidebar taken from master, not
// 2440d79 (four plain tabs there; GAP-211, 218; UXD); the account button stays leading (`MainToolbar.swift:60-66` @ 87fe0d1c, #1057).
// Section titles, sidebar title and the three-column Bookmarks and Alertes Qualitay follow `iPadSidebarRoot` @ 87fe0d1c
// (`MainWindow.swift:1849-1901`, GAP-211, GAP-218, #685).
/// The regular-width iPad root: the legacy sidebar (lists, tools, Plus entries), with the topic list and the reader beside it.
struct RootSidebarView: View {
    @Bindable var model: RootModel
    let environment: AppEnvironment
    /// All columns at launch and not persisted: an intentional difference (legacy defaults to two columns and persists the
    /// choice, `MainWindow.swift:1351`, `:1434-1505`).
    @State private var visibility = NavigationSplitViewVisibility.all
    @State private var compactColumn = NavigationSplitViewColumn.sidebar

    var body: some View {
        layout
            .filteredPosts(model.categories.filtering, reader: environment.reader)
            .filteredPosts(model.favorites.filtering, reader: environment.reader)
    }

    @ViewBuilder
    private var layout: some View {
        if case .plus(let entry) = model.sidebarDestination, !entry.usesTopicList {
            // Legacy: these Plus entries have no list, so a two-column split with the entry in a stack in the detail column
            // (`MainWindow.swift:1326-1333`, `:1865-1872` @ 87fe0d1c).
            NavigationSplitView(columnVisibility: $visibility, preferredCompactColumn: $compactColumn) {
                sidebar.appScreenBackground()
            } detail: {
                // A new identity per entry, so the stack drops what the previous entry had pushed.
                ThemedNavigationStack { PlusEntryView(entry: entry, model: model, environment: environment) }
                    .id(entry)
            }
        } else {
            NavigationSplitView(columnVisibility: $visibility) {
                sidebar.appScreenBackground()
            } content: {
                content.appScreenBackground()
            } detail: {
                detail.appScreenBackground()
            }
        }
    }

    /// The count a sidebar row announces: unread private messages, or the new Alertes Qualitay.
    private func badge(of destination: SidebarDestination) -> Int {
        switch destination {
        case .tab(.messages): model.unreadPrivateMessages
        case .plus(let entry): model.badge(for: entry)
        default: 0
        }
    }

    private var sidebar: some View {
        List(selection: selection) {
            ForEach(SidebarDestination.sections, id: \.self) { section in
                Section(section.title) {
                    ForEach(section.destinations, id: \.self) { destination in
                        Label(destination.title, systemImage: destination.symbol)
                            .foregroundStyle(destination == .plus(.deleteAccount) ? Color.red : Color.primary)
                            .badge(badge(of: destination))
                            .tag(destination)
                    }
                }
            }
        }
        .navigationTitle("Hardware.fr")
        .accountMenuToolbarItem()
    }

    /// A sidebar list selects an optional; deselecting keeps the current destination.
    private var selection: Binding<SidebarDestination?> {
        Binding(get: { model.sidebarDestination }, set: { if let new = $0 { model.selectedDestination = new } })
    }

    @ViewBuilder
    private var content: some View {
        switch model.sidebarDestination {
        case .tab(.categories):
            CategoriesSidebarColumn(navigation: model.categories, composer: environment.composer)
        case .tab(.favorites):
            TopicsColumn(navigation: model.favorites, composer: environment.composer, openCategory: { model.showCategoryFromFavorites($0) })
                .toolbar { ToolbarItem(placement: .primaryAction) { FavoritesSourceMenu(navigation: model.favorites) } }
        case .tab(.messages):
            MessagesListColumn(model: model.messages, composer: environment.composer)
        case .plus(let entry):
            // Bookmarks and Alertes Qualitay: the list in its own stack; a row opens its topic beside it through `openTopicInDetail`.
            PlusListColumn(entry: entry, opener: Self.detailOpener(model: model, environment: environment, entry: entry)) {
                PlusEntryView(entry: entry, model: model, environment: environment)
            }
        case .tab(.more), .tab(.search):
            // Unreachable: `sidebarDestination` maps Plus to Réglages and Recherche to its Plus entry (#896).
            EmptyView()
        }
    }

    @ViewBuilder
    private var detail: some View {
        switch model.sidebarDestination {
        case .tab(.categories): ReaderColumn(navigation: model.categories, reader: environment.reader, composer: environment.composer)
        case .tab(.favorites): ReaderColumn(navigation: model.favorites, reader: environment.reader, composer: environment.composer)
        case .tab(.messages): MessageReaderColumn(model: model.messages, reader: environment.reader, composer: environment.composer)
        case .plus(let entry): PlusDetailColumn(entry: entry, model: model, environment: environment)
        default: ContentUnavailableView("Choisissez un élément", systemImage: "sidebar.left")
        }
    }

    /// What a row of `entry`'s list calls to open a topic in the detail column: a new reader over this session's pages.
    static func detailOpener(model: RootModel, environment: AppEnvironment, entry: PlusEntry) -> OpenTopicInDetail {
        OpenTopicInDetail(
            open: { target, title in
                model.openInDetail(
                    TopicReaderModel(
                        target: target, title: title, source: environment.topicPages,
                        renderOptions: environment.reader.settings.renderOptions
                    ),
                    for: entry
                )
            },
            close: { model.closeDetail(for: entry) }
        )
    }
}

/// Opens a topic in the detail column of the regular-width iPad split: set on the content column of Bookmarks and Alertes
/// Qualitay (#685), nil elsewhere, where a list pushes the topic on its own stack (the Plus tab of the tab bar).
struct OpenTopicInDetail {
    let open: @MainActor (ReaderTarget, String) -> Void
    /// Empties the detail column (a deleted bookmark it showed, LOT-132).
    var close: @MainActor () -> Void = {}

    @MainActor
    func callAsFunction(_ target: ReaderTarget, title: String) { open(target, title) }
}

extension EnvironmentValues {
    /// How a list beside the detail column opens a topic there; nil when the list has no detail column.
    @Entry var openTopicInDetail: OpenTopicInDetail?
}

/// The content column of Bookmarks and Alertes Qualitay: the entry's list in its own stack, a new one per entry, every screen of
/// which (pushed ones too) can open a topic in the detail column.
struct PlusListColumn<Content: View>: View {
    let entry: PlusEntry
    let opener: OpenTopicInDetail
    @ViewBuilder var content: Content

    var body: some View {
        ThemedNavigationStack { content }
            .id(entry)
            .environment(\.openTopicInDetail, opener)
    }
}

/// The detail column of Bookmarks and Alertes Qualitay: the topic a row opened, in its own stack for the readers a link pushes
/// (LOT-137), or legacy's placeholder until one is.
private struct PlusDetailColumn: View {
    let entry: PlusEntry
    let model: RootModel
    let environment: AppEnvironment

    var body: some View {
        if let reader = model.detailReaders[entry] {
            ThemedNavigationStack {
                TopicReaderView(model: reader, services: environment.reader, composer: environment.composer)
            }
            // A newly opened topic is a new stack, as legacy resets the detail (`detailNavigationResetToken`).
            .id(ObjectIdentifier(reader))
        } else if let placeholder = entry.detailPlaceholder {
            ContentUnavailableView(
                placeholder.title, systemImage: placeholder.symbol, description: Text(placeholder.description)
            )
        }
    }
}

/// The category list opening its topics in the same column, so the reader keeps the detail column.
private struct CategoriesSidebarColumn: View {
    @Bindable var navigation: NavigationModel
    let composer: ComposerServices?

    var body: some View {
        ThemedNavigationStack {
            ForumListView(navigation: navigation)
                .navigationDestination(item: $navigation.selectedSource) { source in
                    TopicListView(
                        model: navigation.topicList(for: source), selection: $navigation.selectedTopic, filtering: navigation.filtering,
                        composer: composer, open: { navigation.open($0, at: $1) }, scope: navigation.scope(for: source)
                    )
                    .appScreenBackground()
                }
        }
    }
}
