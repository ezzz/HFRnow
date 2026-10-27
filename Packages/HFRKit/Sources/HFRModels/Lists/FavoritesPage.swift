import Foundation

/// The parsed favourites page (`forum1f.php`): topics grouped by category, plus the session facts the page exposes.
public struct FavoritesPage: Sendable, Hashable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Category sections in page order; empty when the account has no favourite.
    public var sections: [FavoriteSection]
    /// Unread private messages announced by the page header.
    public var unreadPrivateMessages: Int?
    /// The `hash_check` token of the page (a secret: never log it); nil when the page has none.
    public var hashCheck: String?
    /// Message HFR shows instead of the list (R12: "Aucun sujet que vous avez lu n'est connu"); nil on a list page.
    /// It is the page of a logged-out visitor, and possibly of a member with nothing flagged: the caller knows the session.
    public var notice: String?

    /// Creates a favourites page.
    public init(
        sections: [FavoriteSection] = [],
        unreadPrivateMessages: Int? = nil,
        hashCheck: String? = nil,
        notice: String? = nil
    ) {
        self.sections = sections
        self.unreadPrivateMessages = unreadPrivateMessages
        self.hashCheck = hashCheck
        self.notice = notice
    }

    /// Every topic of every section, most recent last post first; topics without a date come last, page order breaks ties.
    public var topicsByLastPost: [TopicSummary] {
        let topics = sections.flatMap(\.topics)
        return topics.enumerated().sorted { lhs, rhs in
            switch (lhs.element.lastPost?.date, rhs.element.lastPost?.date) {
            case let (left?, right?): left != right ? left > right : lhs.offset < rhs.offset
            case (_?, nil): true
            case (nil, _?): false
            case (nil, nil): lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    /// Summary without the token, so logging a page cannot leak it.
    public var description: String {
        let unread = unreadPrivateMessages.map(String.init) ?? "nil"
        let token = hashCheck == nil ? "nil" : "<redacted>"
        return "FavoritesPage(\(sections.count) sections, unreadPrivateMessages: \(unread), hashCheck: \(token))"
    }

    /// Same as `description`.
    public var debugDescription: String { description }

    /// Reflection (`dump`, debugger) hides the token too.
    public var customMirror: Mirror {
        Mirror(self, children: [
            "sections": sections,
            "unreadPrivateMessages": unreadPrivateMessages as Any,
            "hashCheck": hashCheck == nil ? "nil" : "<redacted>"
        ], displayStyle: .struct)
    }
}
