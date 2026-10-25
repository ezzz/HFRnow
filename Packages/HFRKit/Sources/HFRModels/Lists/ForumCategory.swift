/// A forum category of the home page with its sub-forums.
public struct ForumCategory: Sendable, Hashable, Identifiable, Codable {
    /// Stable identity: the forum path, which HFR makes unique per forum.
    public var id: String { path }
    /// HFR `cat` id; nil when it cannot be derived (the home page links do not carry it).
    public var categoryID: CategoryID?
    /// Display title.
    public var title: String
    /// Path of the forum's topic list, relative to the forum base URL.
    public var path: String
    /// Sub-forums in page order; empty when the category has none.
    public var subforums: [ForumLink]

    /// Creates a forum category.
    public init(categoryID: CategoryID? = nil, title: String, path: String, subforums: [ForumLink] = []) {
        self.categoryID = categoryID
        self.title = title
        self.path = path
        self.subforums = subforums
    }
}
