import Foundation

/// What login needs from a profile edit page (`/user/editprofil.php`, HFR-PROTOCOL R6).
public struct ProfileEditPage: Sendable, Equatable {
    /// The account's anti-CSRF token (`hash_check`), never empty.
    public var hashCheck: String
    /// The account's avatar image; nil when the account has none (the row only offers "Créer un avatar").
    public var avatarURL: URL?

    /// Creates a parsed profile edit page.
    public init(hashCheck: String, avatarURL: URL? = nil) {
        self.hashCheck = hashCheck
        self.avatarURL = avatarURL
    }
}
