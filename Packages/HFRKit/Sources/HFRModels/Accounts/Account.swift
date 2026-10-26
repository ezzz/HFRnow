import Foundation

/// A forum account known to the app. No password is ever stored (the login password only lives in memory
/// during login). Cookies and `hash_check` are secrets: descriptions hide them.
public struct Account: Sendable, Hashable, Identifiable, Codable, CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    /// Stable identity: the login pseudo, i.e. the value of the `md_user` cookie.
    public var id: String { pseudo }
    /// Login pseudo (value of the `md_user` cookie).
    public var pseudo: String
    /// Pseudo as displayed on the forum (case may differ from the login pseudo).
    public var displayName: String
    /// Session cookies of the account.
    public var cookies: [StoredCookie]
    /// The `hash_check` token needed to post; nil until a page exposed it.
    public var hashCheck: String?
    /// Avatar image bytes, if downloaded.
    public var avatarData: Data?
    /// Whether this is the main account (the one whose cookies the shared jar carries).
    public var isMain: Bool

    /// Creates an account.
    public init(
        pseudo: String,
        displayName: String? = nil,
        cookies: [StoredCookie] = [],
        hashCheck: String? = nil,
        avatarData: Data? = nil,
        isMain: Bool = false
    ) {
        self.pseudo = pseudo
        self.displayName = displayName ?? pseudo
        self.cookies = cookies
        self.hashCheck = hashCheck
        self.avatarData = avatarData
        self.isMain = isMain
    }

    /// Description without cookies or token.
    public var description: String {
        "Account(\(pseudo), main: \(isMain), \(cookies.count) cookies, secrets hidden)"
    }

    /// Same as `description`.
    public var debugDescription: String { description }

    /// Reflection (`dump`, debugger) hides cookies, token and avatar bytes.
    public var customMirror: Mirror {
        Mirror(self, children: [
            "pseudo": pseudo, "displayName": displayName, "cookies": "\(cookies.count) cookies, redacted",
            "hashCheck": hashCheck == nil ? "nil" : "<redacted>", "avatarBytes": avatarData?.count as Any, "isMain": isMain
        ], displayStyle: .struct)
    }
}
