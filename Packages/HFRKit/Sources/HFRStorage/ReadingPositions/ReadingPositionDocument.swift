/// Everything the reading-position store persists, in one file so a save is atomic across accounts.
public struct ReadingPositionDocument: Sendable, Hashable, Codable {
    /// Format version written by this code. A larger version on disk is never overwritten (see `ReadingPositionStore`).
    public static let currentVersion = 1

    /// Format version.
    public var version: Int
    /// Records keyed by the account identifier (`Account.id`), one per topic, in no particular order.
    public var accounts: [String: [ReadingPositionRecord]]

    /// Creates a document.
    public init(version: Int = ReadingPositionDocument.currentVersion, accounts: [String: [ReadingPositionRecord]] = [:]) {
        self.version = version
        self.accounts = accounts
    }
}
