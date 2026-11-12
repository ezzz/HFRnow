import SwiftUI

// Port of HFRswift/Swift/MainWindow.swift (CategoriesListView, forumRowLabel, `:129-262`) @ 87fe0d1c. Differences: explicit inset-grouped
// style like the MP list (#427, #572) instead of the default list; the sub-forums are chosen from the topic list's menu, as in
// legacy (GAP-020, 021, 022); "1 sous-forum" in the singular.
/// The Catégories list: one flat row per forum with its icon and sub-forum count (flags and favourites have their own tab, LOT-170).
struct ForumListView: View {
    @Bindable var navigation: NavigationModel

    var body: some View {
        let loader = navigation.forums.loader
        List(selection: $navigation.selectedSource) {
            if let content = loader.value {
                // Noël soft piles a little snow on the card's top edge, in the section header above it (LOT-166).
                SeasonalSnowCapSection {
                    ForEach(content.sections) { section in
                        row(section).densityRowMargin().tag(section.source)
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .densityListMargins()
        .seasonalScrollTracking()
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

    private func row(_ section: ForumSection) -> some View {
        HStack(spacing: 12) {
            ForumCategoryIconView(assetName: section.iconName)
            VStack(alignment: .leading, spacing: 4) {
                Text(section.title)
                if section.subforumCount > 0 {
                    Text(FrenchPlural.count(section.subforumCount, "sous-forum", "sous-forums"))
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
    }
}
