/// Everything the super-favourites store persists, in one file so a save is atomic across accounts.
public struct SuperFavoritesDocument: SmallStoreDocument {
    /// Format version written by this code.
    public static let currentVersion = 1
    /// A document without any super-favourite.
    public static var empty: Self { Self() }

    /// Format version.
    public var version: Int
    /// Super-favourites keyed by account key (ADR 0013 §7), each list sorted by category then topic number.
    public var accounts: [String: [SuperFavorite]]

    /// Creates a document.
    public init(version: Int = Self.currentVersion, accounts: [String: [SuperFavorite]] = [:]) {
        self.version = version
        self.accounts = accounts
    }
}
