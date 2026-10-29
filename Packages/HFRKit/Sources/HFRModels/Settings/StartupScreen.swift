/// The `HFRswiftStartupScreen` setting: where the app opens. Raw values are the legacy tab identifiers.
public enum StartupScreen: String, Sendable, Codable, CaseIterable {
    /// The forum list (legacy "Tab Catégories").
    case categories = "tab:categories"
    /// The favourites (legacy "Tab Favoris", the default).
    case favorites = "tab:favorites"
    /// The private messages (legacy "Tab Messages").
    case messages = "tab:messages"
}
