import HFRModels
import HFRStorage

/// What the middle column lists: a forum, the flagged topics or the favourites.
enum TopicSource: Hashable, Sendable {
    case forum(CategoryID, title: String)
    /// A forum (sub-forum or category) opened from the forum-relative link the home page gives, `/hfr/<cat>/<sub>/liste_sujet-1.htm`.
    case subforum(path: String, title: String)
    case flagged
    case favorites

    /// Navigation title of the topic list.
    var title: String {
        switch self {
        case .forum(_, let title), .subforum(_, let title): title
        case .flagged: "Drapeaux"
        case .favorites: "Favoris"
        }
    }

    /// Forum lists are paged; flags and favourites are one page.
    var isPaged: Bool {
        switch self {
        case .forum, .subforum: true
        case .flagged, .favorites: false
        }
    }
}

extension TopicSource {
    /// A forum's list (category or sub-forum), as opposed to the flags and the favourites.
    var isForumList: Bool { isPaged }

    /// A category's own list takes the Tous / Favoris / Suivis / Lus filter (`owntopic`, R2); a sub-forum opened from its link
    /// does not, as the link carries no `subcat` id (`R603d` shows `subcat=<s>` works; where the id comes from is pending capture).
    var supportsFlagFilter: Bool {
        if case .forum = self { return true }
        return false
    }

    /// The two lists the favourites options apply to.
    var isFavoritesList: Bool { self == .flagged || self == .favorites }

    /// The favourites mode (`vos_sujets`) this source stands for: the flags list is "Drapeaux & Favoris", the favourites
    /// list "Favoris uniquement" (`ObjCFavoritesLoaderWorker.m:45-48`).
    var favoritesMode: FavoritesSource? {
        switch self {
        case .flagged: .flagsAndFavorites
        case .favorites: .favoritesOnly
        case .forum, .subforum: nil
        }
    }

    /// The source a favourites mode opens.
    init(mode: FavoritesSource) {
        self = mode == .favoritesOnly ? .favorites : .flagged
    }
}
