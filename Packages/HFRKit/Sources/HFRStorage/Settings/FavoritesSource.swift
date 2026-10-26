/// The `vos_sujets` setting: which server list the Favorites tab shows.
public enum FavoritesSource: Int, Sendable, Codable, CaseIterable {
    /// Flags and favorites (`forum1f.php?owntopic=1`, default).
    case flagsAndFavorites = 0
    /// Favorites only (`owntopic=3`).
    case favoritesOnly = 1

    /// Legacy `ObjCFavoritesLoaderWorker.m:45-46` tests `== 1`; any other integer means flags and favorites.
    static func legacyDecode(_ number: Int) -> FavoritesSource {
        number == 1 ? .favoritesOnly : .flagsAndFavorites
    }
}
