/// A titled link to a forum (sub-category) page, as the home page and the favourites page present them.
public struct ForumLink: Sendable, Hashable, Codable {
    /// Display title of the forum.
    public var title: String
    /// HFR path of the forum's topic list, relative to the forum base URL.
    public var path: String

    /// Creates a forum link.
    public init(title: String, path: String) {
        self.title = title
        self.path = path
    }
}
