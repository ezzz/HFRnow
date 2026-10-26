/// A parsed topic list page: forum topics, private messages or search results.
public struct TopicListPage: Sendable, Hashable, Codable {
    /// Rows in page order; empty when the page has no results.
    public var topics: [TopicSummary]
    /// Pagination of the list.
    public var navigation: PageNavigation
    /// Links to the list variants.
    public var tabs: TopicListTabs
    /// Category the list belongs to, when the page says so.
    public var categoryID: CategoryID?
    /// Path of the "new topic" form, present when the user may post.
    public var newTopicPath: String?
    /// Unread private messages announced by the page header.
    public var unreadPrivateMessages: Int?
    /// Message HFR shows instead of the list (an empty filter or search: "Aucun favori n'est repertorié"); nil on a list page.
    public var notice: String?

    /// Creates a topic list page.
    public init(
        topics: [TopicSummary] = [],
        navigation: PageNavigation = PageNavigation(),
        tabs: TopicListTabs = TopicListTabs(),
        categoryID: CategoryID? = nil,
        newTopicPath: String? = nil,
        unreadPrivateMessages: Int? = nil,
        notice: String? = nil
    ) {
        self.topics = topics
        self.navigation = navigation
        self.tabs = tabs
        self.categoryID = categoryID
        self.newTopicPath = newTopicPath
        self.unreadPrivateMessages = unreadPrivateMessages
        self.notice = notice
    }
}
