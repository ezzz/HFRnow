/// Everything the pseudo lists persist, in one file so a save is atomic across lists.
public struct PseudoListDocument: Sendable, Hashable, Codable {
    /// Format version written by this code. A larger version on disk is never overwritten (see `PseudoListStore`).
    public static let currentVersion = 1

    /// Format version.
    public var version: Int
    /// Blocklists keyed by the normalised account identifier.
    public var blocklists: [String: [PseudoListEntry]]
    /// The allowlist, shared by all accounts (legacy `whiteList.plist` is global).
    public var allowlist: [PseudoListEntry]

    /// Creates a document.
    public init(
        version: Int = PseudoListDocument.currentVersion,
        blocklists: [String: [PseudoListEntry]] = [:],
        allowlist: [PseudoListEntry] = []
    ) {
        self.version = version
        self.blocklists = blocklists
        self.allowlist = allowlist
    }
}
