import HFRModels

extension StartupScreen {
    /// Picker label (legacy `startupTabOptions`, `AppSettingsView.swift:134-138`).
    var title: String {
        switch self {
        case .categories: "Tab Catégories"
        case .favorites: "Tab Favoris"
        case .messages: "Tab Messages"
        }
    }
}
