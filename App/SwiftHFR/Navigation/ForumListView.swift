import SwiftUI

// Port of HFRswift/Swift/MainWindow.swift (CategoriesListView, forumRowLabel, `:129-262`) @ 87fe0d1c. Differences: explicit inset-grouped
// style like the MP list (#427, #572) instead of the default list; the sub-forums are chosen from the topic list's menu, as in
// legacy (GAP-020, 021, 022); "1 sous-forum" in the singular. #1107: the list look (`listLook`) of every list; the dense look keeps
// the icons with less height and a wider icon gap (`DenseListLook`).
/// The Catégories list: one flat row per forum with its icon and sub-forum count (flags and favourites have their own tab, LOT-170).
struct ForumListView: View {
    @Bindable var navigation: NavigationModel
    @State private var titleVisibility = TitleVisibility()
    @Environment(ExperimentalSettings.self) private var experimental: ExperimentalSettings?

    var body: some View {
        let loader = navigation.forums.loader
        let look = ListLook.current(experimental)
        List(selection: $navigation.selectedSource) {
            // #1107: every row of the list takes its look, once for the whole content.
            Group {
                ScreenLargeTitle(title: "Catégories", visibility: titleVisibility)
                if let content = loader.value {
                    // Noël soft piles a little snow on the card's top edge, in the section header above it (LOT-166).
                    SeasonalSnowCapSection {
                        ForEach(content.sections) { section in
                            row(section, look: look).themedRowText().densityRowMargin().denseCategoryRowInsets(look)
                                .listLookRow(isSelected: navigation.selectedSource == section.source)
                                .tag(section.source)
                        }
                    }
                }
            }
            .listLookRows()
        }
        .listLook()
        .seasonalScrollTracking()
        .screenTitle("Catégories", style: .largeThenPill, visibility: titleVisibility)
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

    private func row(_ section: ForumSection, look: ListLook) -> some View {
        // EXPERIMENTAL(denseRows, #1107): the dense look replaces the classic spacings (12 and 4).
        HStack(spacing: look == .dense ? DenseListLook.categoryIconSpacing : 12) {
            ForumCategoryIconView(assetName: section.iconName)
            VStack(alignment: .leading, spacing: look == .dense ? DenseListLook.categoryLineSpacing : 4) {
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
