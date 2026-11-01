/// Everything the app smiley favourites store persists, in one file so a save is atomic across accounts.
public struct AppSmileyFavoritesDocument: SmallStoreDocument {
    /// Format version written by this code.
    public static let currentVersion = 1
    /// A document without any favourite.
    public static var empty: Self { Self() }

    /// Format version.
    public var version: Int
    /// Favourites keyed by account key (ADR 0013 §7), each list oldest first.
    public var accounts: [String: [AppSmileyFavorite]]

    /// Creates a document.
    public init(version: Int = Self.currentVersion, accounts: [String: [AppSmileyFavorite]] = [:]) {
        self.version = version
        self.accounts = accounts
    }
}
