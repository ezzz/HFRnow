import Foundation

/// What a validated login tells the app about the account. The secrets (cookies, `hash_check`) stay in the session:
/// the app persists them with `HFRSession.cookies(now:)` and `HFRSession.hashCheck`.
public struct LoginResult: Sendable, Equatable {
    /// Raw value of the `md_user` cookie, which HFR URL-encodes (HFR-PROTOCOL §5): the account's stable key.
    /// Persist `Account.pseudo` from this value, and pass it back as `expectedUserKey`; it can differ from `displayName`
    /// for a pseudo with a space or an accent.
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
