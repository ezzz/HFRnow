import Foundation
import HFRModels

/// One account of the legacy Keychain item `HFR_COMPTES_KEY`, decoded (`Constants.h:116-122`, `MultisManager.m:49-80`).
/// Holds secrets: never log it; its description hides them.
public struct LegacyAccountRecord: Sendable, Hashable, CustomStringConvertible, CustomDebugStringConvertible {
    /// `PSEUDO`: the `md_user` cookie value (absent when the session had none).
    public var pseudo: String?
    /// `PSEUDO_DISPLAY`: the name typed at login.
    public var displayName: String?
    /// `COOKIES`.
    public var cookies: [StoredCookie]
    /// `HASH`.
    public var hashCheck: String?
    /// `AVATAR`.
    public var avatarData: Data?
    /// `MAIN`.
    public var isMain: Bool

    /// Creates a record.
    public init(
        pseudo: String?,
        displayName: String?,
        cookies: [StoredCookie] = [],
        hashCheck: String? = nil,
        avatarData: Data? = nil,
        isMain: Bool = false
    ) {
        self.pseudo = pseudo
        self.displayName = displayName
        self.cookies = cookies
        self.hashCheck = hashCheck
        self.avatarData = avatarData
        self.isMain = isMain
    }

    /// Description without cookies or token.
    public var description: String {
        "LegacyAccountRecord(\(cookies.count) cookies, main: \(isMain), secrets hidden)"
    }

    /// Same as `description`.
    public var debugDescription: String { description }
}

/// Where the legacy accounts are read. Never writes or deletes the legacy item.
public protocol LegacyAccountSource: Sendable {
    /// The legacy accounts in stored order; empty when the item is absent. Throws `LegacyImportError.sourceUnreadable`
    /// when the item exists but is not a legacy archive, `.sourceUnavailable` when it cannot be read now (device
    /// locked): the step is then retried.
    func accounts() throws(LegacyImportError) -> [LegacyAccountRecord]
}

/// Fixed legacy accounts, for tests and on platforms without a Keychain.
public struct InMemoryLegacyAccountSource: LegacyAccountSource {
    private let result: Result<[LegacyAccountRecord], LegacyImportError>

    /// Creates a source answering `accounts`.
    public init(_ accounts: [LegacyAccountRecord] = []) {
        result = .success(accounts)
    }

    /// Creates a source that fails with `error`.
    public init(failing error: LegacyImportError) {
        result = .failure(error)
    }

    public func accounts() throws(LegacyImportError) -> [LegacyAccountRecord] {
        try result.get()
    }
}
