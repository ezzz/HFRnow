import HFRModels

/// The Tous / Favoris / Suivis / Lus choice of a forum's topic list (legacy `TopicListFlag`, `Common.swift:1725` @ 87fe0d1c).
///
/// The raw values are legacy's (`HFRswiftGlobalTopicListFlag` holds one), which are not HFR's `owntopic` numbers: `filter` maps them.
public enum TopicListFlag: Int, Sendable, CaseIterable {
    /// "Tous": the forum's own list.
    case all = 0
    /// "Favoris": `owntopic=3`.
    case favorites = 1
    /// "Suivis": `owntopic=1`.
    case tracked = 2
    /// "Lus": `owntopic=2`.
    case read = 3

    /// The list HFR serves for this choice (`ObjCForumTopicsLoaderWorker.m` `fetchContentForForum:flagIndex:` @ 87fe0d1c).
    public var filter: TopicListFilter {
        switch self {
        case .all: .all
        case .favorites: .favorites
        case .tracked: .flagged
        case .read: .read
        }
    }
}
