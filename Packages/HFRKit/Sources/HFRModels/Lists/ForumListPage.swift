/// The parsed home page: forum categories plus the session facts the page exposes.
public struct ForumListPage: Sendable, Hashable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Categories in page order (all of them: hiding some is an app policy).
    public var forums: [ForumCategory]
    /// Whether the page shows a logged-in session.
    public var isLoggedIn: Bool
    /// Unread private messages announced by the page header.
    public var unreadPrivateMessages: Int?
    /// The `hash_check` token of the page (a secret: never log it); nil when logged out.
    public var hashCheck: String?

    /// Creates a forum list page.
    public init(forums: [ForumCategory], isLoggedIn: Bool = false, unreadPrivateMessages: Int? = nil, hashCheck: String? = nil) {
        self.forums = forums
        self.isLoggedIn = isLoggedIn
        self.unreadPrivateMessages = unreadPrivateMessages
        self.hashCheck = hashCheck
    }

    /// Summary without the token, so logging a page cannot leak it.
    public var description: String {
        let unread = unreadPrivateMessages.map(String.init) ?? "nil"
        let token = hashCheck == nil ? "nil" : "<redacted>"
        return "ForumListPage(\(forums.count) forums, loggedIn: \(isLoggedIn), unreadPrivateMessages: \(unread), hashCheck: \(token))"
    }

    /// Same as `description`.
    public var debugDescription: String { description }

    /// Reflection (`dump`, debugger) hides the token too.
    public var customMirror: Mirror {
        Mirror(self, children: [
            "forums": forums,
            "isLoggedIn": isLoggedIn,
            "unreadPrivateMessages": unreadPrivateMessages as Any,
            "hashCheck": hashCheck == nil ? "nil" : "<redacted>"
        ], displayStyle: .struct)
    }
}
