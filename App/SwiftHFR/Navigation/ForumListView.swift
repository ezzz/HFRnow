import SwiftUI

/// The Catégories list: every forum with its sub-forums (flags and favourites have their own tab, LOT-170).
struct ForumListView: View {
    @Bindable var navigation: NavigationModel

    var body: some View {
        let loader = navigation.forums.loader
        List(selection: $navigation.selectedSource) {
            if let content = loader.value {
                ForEach(content.sections) { section in
                    Section(section.title, isExpanded: expansion(of: section.id)) {
                        ForEach(section.rows) { row in
                            Text(row.title).tag(row.source)
                        }
                    }
                }
            }
        }
        .listStyle(.sidebar)
        .navigationTitle("Catégories")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                AccountMenuButton()
            }
        }
        .overlay { overlay(loader) }
        .safeAreaInset(edge: .top) {
            if let error = loader.error, loader.value != nil {
                LoadFailureBanner(error: error, retry: navigation.forums.reload)
            }
        }
        .refreshable { await navigation.forums.reload() }
        .task { await navigation.forums.loadIfNeeded() }
        .onChange(of: navigation.selectedSource) { _, source in navigation.forums.reveal(source) }
    }

    @ViewBuilder
    private func overlay(_ loader: ContentLoader<ForumListContent>) -> some View {
        if loader.value == nil {
            if let error = loader.error {
                LoadFailureView(error: error, retry: navigation.forums.reload)
            } else if loader.isLoading {
                ProgressView("Chargement des forums")
            }
        }
    }

    private func expansion(of id: String) -> Binding<Bool> {
        Binding(
            get: { navigation.forums.expandedSections.contains(id) },
            set: { open in
                if open { navigation.forums.expandedSections.insert(id) } else { navigation.forums.expandedSections.remove(id) }
            }
        )
    }
}
