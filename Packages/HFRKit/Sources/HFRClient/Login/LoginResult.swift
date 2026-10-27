import Foundation

/// What a validated login tells the app about the account. The secrets (cookies, `hash_check`) stay in the session:
/// the app persists them with `HFRSession.cookies(now:)` and `HFRSession.hashCheck`.
public struct LoginResult: Sendable, Equatable {
    /// Value of the `md_user` cookie set by the login: the account's stable key (`Account.pseudo`).
    public var userKey: String
    /// The pseudo as submitted (trimmed), for display (legacy `displayPseudo`).
    public var displayName: String
    /// The account's avatar from the profile page, nil when it has none. Not a forum page: fetch it through
    /// `AnonymousTransport`, never with the account session.
    public var avatarURL: URL?

    /// Creates a login result.
    public init(userKey: String, displayName: String, avatarURL: URL? = nil) {
        self.userKey = userKey
        self.displayName = displayName
        self.avatarURL = avatarURL
    }
}
