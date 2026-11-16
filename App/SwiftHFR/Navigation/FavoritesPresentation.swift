import HFRModels

/// How the favourites list is laid out, from the legacy settings (`sujets_avec_cat`, `FavoritesShowCollapsedSections`).
struct FavoritesLayoutOptions: Equatable, Sendable {
    /// Sections by category (`sujets_avec_cat`), else one flat list by last post.
    var groupedByCategory: Bool
    /// Collapsed sections stay listed (header only).
    var showsCollapsedSections: Bool
    /// Categories without any topic stay listed.
    var showsEmptySections: Bool
}

// Port of HFRswift/Swift/Favorites.swift (FavoritesListView display rules, FavoritesTopicListOrdering) @ 2440d79.
// Differences: GAP-030, GAP-031, GAP-033 (super-favourites are a section, not only a tint).
/// Turns a favourites page into the groups the list shows (LOT-124).
///
/// Port of `FavoritesListView` (`Favorites.swift` @ 2440d79: `shouldDisplayCategorizedFavorite`, `collapsibleSectionIDs`,
/// `FavoritesTopicListOrdering.flattenedTopics`). Pure: no store, no setting, so every rule is testable on its own.
enum FavoritesPresentation {
    /// Identity of the super-favourites section.
    static let superFavoritesSectionID = "super-favorites"

    /// The groups to show. Grouped: super-favourites first (each topic only there, so a row never appears twice), then the
    /// categories in page order, a collapsed one keeping its header. Flat: every topic by last post, one headless group.
    static func groups(
        of page: FavoritesPage, options: FavoritesLayoutOptions, collapsed: Set<String>, superFavorites: Set<TopicID>
    ) -> [TopicGroup] {
        guard options.groupedByCategory else {
            let topics = page.topicsByLastPost
            return topics.isEmpty ? [] : [TopicGroup(id: "topics", title: nil, topics: topics)]
        }
        var result: [TopicGroup] = []
        let supers = page.sections.flatMap(\.topics).filter { isSuper($0, in: superFavorites) }
        if !supers.isEmpty {
            result.append(TopicGroup(id: superFavoritesSectionID, title: "Super favoris", topics: supers))
        }
        for section in page.sections {
            let topics = section.topics.filter { !isSuper($0, in: superFavorites) }
            let isCollapsed = collapsed.contains(section.id) && !topics.isEmpty
            if collapsed.contains(section.id), !options.showsCollapsedSections { continue }
            guard !topics.isEmpty || options.showsEmptySections else { continue }
            result.append(TopicGroup(
                id: section.id, title: section.forum.title, topics: topics, isCollapsible: !topics.isEmpty, isCollapsed: isCollapsed,
                opens: section.source
            ))
        }
        return result
    }

    /// Sections the user can fold: those holding a topic once super-favourites are taken out (legacy `collapsibleSectionIDs`).
    static func collapsibleSectionIDs(of page: FavoritesPage, superFavorites: Set<TopicID>) -> Set<String> {
        Set(page.sections.filter { $0.topics.contains { !isSuper($0, in: superFavorites) } }.map(\.id))
    }

    /// Whether `topic` is a super-favourite; a row without a topic identity never is.
    static func isSuper(_ topic: TopicSummary, in superFavorites: Set<TopicID>) -> Bool {
        topic.topicID.map(superFavorites.contains) ?? false
    }
}

extension FavoriteSection {
    /// The category the section's title opens; nil without a category id (the page's own header link is already filtered, so
    /// opening it would not match the filter control).
    var source: TopicSource? {
        categoryID.map { TopicSource.forum($0, title: forum.title) }
    }
}
