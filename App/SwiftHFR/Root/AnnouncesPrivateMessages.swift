import HFRModels

/// A list page whose header may carry HFR's unread private messages count.
protocol AnnouncesPrivateMessages {
    /// The count the page's header announced; nil when it has no private messages entry.
    var announcedUnreadPrivateMessages: Int? { get }
}

extension ForumListPage: AnnouncesPrivateMessages {
    var announcedUnreadPrivateMessages: Int? { unreadPrivateMessages }
}

extension TopicListPage: AnnouncesPrivateMessages {
    var announcedUnreadPrivateMessages: Int? { unreadPrivateMessages }
}

extension FavoritesPage: AnnouncesPrivateMessages {
    var announcedUnreadPrivateMessages: Int? { unreadPrivateMessages }
}
