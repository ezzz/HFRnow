/// One category section of the favourites page (not a single favourite topic).
public struct FavoriteSection: Sendable, Hashable, Identifiable, Codable {
    /// Stable identity: `cat:<id>` when the category id is known, else `path:<forum path>`.
    public var id: String {
        if let categoryID {
            return "cat:\(categoryID.queryValue)"
        }
        return "path:\(forum.path)"
    }

    /// The forum header link of the section.
    public var forum: ForumLink
    /// Category id read from the header link.
    public var categoryID: CategoryID?
    /// Favourite topics of the category; their `topicID` is expected to be set.
    public var topics: [TopicSummary]

    /// Creates a favourites section.
    public init(forum: ForumLink, categoryID: CategoryID? = nil, topics: [TopicSummary] = []) {
        self.forum = forum
        self.categoryID = categoryID
        self.topics = topics
    }
}
