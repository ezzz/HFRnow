/// What the smiley search history persists: device-only, global (ADR 0013, appendix E).
public struct SmileySearchHistoryDocument: SmallStoreDocument {
    /// Format version written by this code.
    public static let currentVersion = 1
    /// An empty history.
    public static var empty: Self { Self() }

    /// Format version.
    public var version: Int
    /// The remembered searches, the last one recorded first, then the most recent first (the views sort them anyway).
    public var entries: [SmileySearchHistoryEntry]

    /// Creates a document.
    public init(version: Int = Self.currentVersion, entries: [SmileySearchHistoryEntry] = []) {
        self.version = version
        self.entries = entries
    }
}
