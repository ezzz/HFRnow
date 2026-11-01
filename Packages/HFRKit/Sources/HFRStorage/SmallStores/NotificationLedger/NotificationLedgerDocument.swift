/// Everything the notification ledger store persists, in one file so a save is atomic across accounts.
public struct NotificationLedgerDocument: SmallStoreDocument {
    /// Format version written by this code.
    public static let currentVersion = 1
    /// A document without any ledger.
    public static var empty: Self { Self() }

    /// Format version.
    public var version: Int
    /// Ledgers keyed by account key (ADR 0013 §7).
    public var accounts: [String: NotificationLedger]

    /// Creates a document.
    public init(version: Int = Self.currentVersion, accounts: [String: NotificationLedger] = [:]) {
        self.version = version
        self.accounts = accounts
    }
}
