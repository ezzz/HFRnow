/// Paths of the list variants a forum page offers (the tabs above the topic list).
public struct TopicListTabs: Sendable, Hashable, Codable {
    /// Path of the list of all topics.
    public var all: String?
    /// Path of the favourites list.
    public var favorites: String?
    /// Path of the list filtered on the blue flag.
    public var flagBlue: String?
    /// Path of the list filtered on the red flag.
    public var flagRed: String?

    /// Creates the tab links.
    public init(all: String? = nil, favorites: String? = nil, flagBlue: String? = nil, flagRed: String? = nil) {
        self.all = all
        self.favorites = favorites
        self.flagBlue = flagBlue
        self.flagRed = flagRed
    }
}
