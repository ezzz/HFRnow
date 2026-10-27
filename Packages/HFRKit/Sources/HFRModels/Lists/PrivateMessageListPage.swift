/// A page of the private messages list (`cat=prive`).
public struct PrivateMessageListPage: Sendable, Hashable, Codable {
    /// Conversations in page order; empty for an empty mailbox.
    public var threads: [PrivateMessageThread]
    /// Pagination of the list (the legacy list read page 1 only).
    public var navigation: PageNavigation
    /// Path of the "new private message" form, when the page links to it.
    public var newMessagePath: String?

    /// Conversations of this page with an unread message for the member. A page is not the whole mailbox: the member's
    /// total comes from the badge (`PrivateMessageBadgeParser`).
    public var unreadThreadCount: Int { threads.filter(\.isUnread).count }

    /// Creates a private messages list page.
    public init(threads: [PrivateMessageThread] = [], navigation: PageNavigation = PageNavigation(), newMessagePath: String? = nil) {
        self.threads = threads
        self.navigation = navigation
        self.newMessagePath = newMessagePath
    }
}
