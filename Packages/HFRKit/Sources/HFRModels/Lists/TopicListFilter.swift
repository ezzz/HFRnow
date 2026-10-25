/// The `owntopic` query value that selects which topics a list shows.
public enum TopicListFilter: Int, Sendable {
    /// Every topic of the forum.
    case all = 0
    /// Topics carrying a flag (tracked).
    case flagged = 1
    /// Topics the user has read.
    case read = 2
    /// Topics in the user's favourites.
    case favorites = 3
}
