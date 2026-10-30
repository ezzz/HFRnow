/// What the favourites layout store persists: device-only presentation state (ADR 0013, appendix E).
public struct FavoritesLayoutDocument: SmallStoreDocument {
    /// Format version written by this code.
    public static let currentVersion = 1
    /// A document with every section expanded.
    public static var empty: Self { Self() }

    /// Format version.
    public var version: Int
    /// Identifiers of the collapsed favourites sections, trimmed, without duplicates, sorted.
    public var collapsedSections: [String]

    /// Creates a document.
    public init(version: Int = Self.currentVersion, collapsedSections: [String] = []) {
        self.version = version
        self.collapsedSections = collapsedSections
    }
}
