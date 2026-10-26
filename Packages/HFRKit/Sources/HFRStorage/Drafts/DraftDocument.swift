/// Everything the draft store persists.
public struct DraftDocument: Sendable, Hashable, Codable {
    /// Format version written by this code.
    public static let currentVersion = 1

    /// Format version.
    public var version: Int
    /// Drafts, at most one per account and context.
    public var drafts: [Draft]

    /// Creates a document.
    public init(version: Int = DraftDocument.currentVersion, drafts: [Draft] = []) {
        self.version = version
        self.drafts = drafts
    }
}
