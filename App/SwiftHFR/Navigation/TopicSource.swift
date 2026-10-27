import HFRModels

/// What the middle column lists: a forum, the flagged topics or the favourites.
enum TopicSource: Hashable, Sendable {
    case forum(CategoryID, title: String)
    case flagged
    case favorites

    /// Navigation title of the topic list.
    var title: String {
        switch self {
        case .forum(_, let title): title
        case .flagged: "Drapeaux"
        case .favorites: "Favoris"
        }
    }

    /// Forum lists are paged; flags and favourites are one page.
    var isPaged: Bool {
        if case .forum = self { true } else { false }
    }
}
