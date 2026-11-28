import HFRModels

/// How the favourites list is laid out, from the legacy settings (`sujets_avec_cat`, `FavoritesShowCollapsedSections`).
struct FavoritesLayoutOptions: Equatable, Sendable {
    /// Sections by category (`sujets_avec_cat`), else one flat list by last post.
    var groupedByCategory: Bool
    /// Collapsed sections stay listed (header only).
    var showsCollapsedSections: Bool
    /// Categories without any topic stay listed.
    var showsEmptySections: Bool
    /// « Non lus »: only the rows the list shows with unread pages (#1058, new in SwiftHFR); « Tous » (false) is the legacy view.
    var unreadOnly = false
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

    /// The layout to draw: with the flat sort, the on-demand view groups by category and shows every folded section, as legacy's
    /// `usesCategorizedFavoritesList` and `showsAllFavoriteSections` (`Favorites.swift:488-494` @ 87fe0d1c). In the grouped sort it
    /// changes nothing (there the button is « sections repliées », a setting). The on-demand view also lists the empty
    /// categories where the list kind allows them (`shouldShowEmptyFavoriteSections`, `:496-497`): `emptySectionsAllowed`.
    static func effectiveLayout(
        of layout: FavoritesLayoutOptions, categoriesOnDemand: Bool, emptySectionsAllowed: Bool
    ) -> FavoritesLayoutOptions {
        guard categoriesOnDemand, !layout.groupedByCategory else { return layout }
        var result = layout
        result.groupedByCategory = true
        result.showsCollapsedSections = true
        result.showsEmptySections = emptySectionsAllowed
        return result
    }

    /// The groups to show. Grouped: super-favourites first (each topic only there, so a row never appears twice), then the
    /// categories in page order, a collapsed one keeping its header. Flat: every topic by last post, one headless group.
    static func groups(
        of page: FavoritesPage, options: FavoritesLayoutOptions, collapsed: Set<String>, superFavorites: Set<TopicID>
    ) -> [TopicGroup] {
        // « Non lus » (#1058) keeps the rows that carry the unread-pages badge; a section it empties follows the empty-sections rule.
        func shown(_ topics: [TopicSummary]) -> [TopicSummary] { options.unreadOnly ? topics.filter(isUnread) : topics }
        guard options.groupedByCategory else {
            let topics = shown(page.topicsByLastPost)
            return topics.isEmpty ? [] : [TopicGroup(id: "topics", title: nil, topics: topics)]
        }
        var result: [TopicGroup] = []
        let supers = shown(page.sections.flatMap(\.topics).filter { isSuper($0, in: superFavorites) })
        if !supers.isEmpty {
            result.append(TopicGroup(id: superFavoritesSectionID, title: "Super favoris", topics: supers))
        }
        for section in page.sections {
            let topics = shown(section.topics.filter { !isSuper($0, in: superFavorites) })
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

    /// Sections the user can fold: those holding a topic once super-favourites are taken out (legacy `collapsibleSectionIDs`);
    /// under « Non lus » (#1058), those with an unread one, so "Tout replier" never folds a section the list does not show.
    static func collapsibleSectionIDs(
        of page: FavoritesPage, superFavorites: Set<TopicID>, unreadOnly: Bool = false
    ) -> Set<String> {
        Set(page.sections.filter {
            $0.topics.contains { !isSuper($0, in: superFavorites) && (!unreadOnly || isUnread($0)) }
        }.map(\.id))
    }

    /// Whether a favourites row shows as unread: its flag is pages behind the end of the topic, which is the badge the row draws
    /// (`TopicRowCues.unreadPages`, legacy `unreadCount` = `maxTopicPage - curTopicPage`, `Favorites.swift:1096-1100` @ 87fe0d1c, badge
    /// only above 0, `:1130-1131`). Favourites rows carry no `sujetCase1` marker (`readState` is `.unknown`), so that is the state to use.
    static func isUnread(_ topic: TopicSummary) -> Bool {
        TopicRowCues.unreadPages(topic) != nil
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
