import HFRModels

extension StartupScreen {
    /// Picker label (legacy `startupTabOptions`, `AppSettingsView.swift:134-138`, as legacy).
    /// The tab bar is absent only until LOT-170 (#296) restores it.
    var title: String {
        switch self {
        case .categories: "Tab Catégories"
        case .favorites: "Tab Favoris"
        case .messages: "Tab Messages"
        }
    }

    /// The sidebar entry chosen at launch. Nil opens the forum list; the private messages have no screen yet (LOT-126),
    /// so they open the forum list too rather than a guessed destination.
    var initialSource: TopicSource? {
        switch self {
        case .favorites: .favorites
        case .categories, .messages: nil
        }
    }
}
