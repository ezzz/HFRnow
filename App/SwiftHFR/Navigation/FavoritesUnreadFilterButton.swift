import SwiftUI

// New in SwiftHFR (#1058, operator feedback 2026-11-17): a deliberate gap, legacy's Favoris has no unread/all toggle
// (`Favorites.swift:581-594` @ 87fe0d1c filters by collapse state only). Differences: none to port.
/// The Favoris top bar's « Non lus / Tous » toggle: one tap, no menu, its icon shows the state.
struct FavoritesUnreadFilterButton: View {
    @Bindable var options: FavoritesOptionsModel

    var body: some View {
        let content = Content.make(unreadOnly: options.unreadOnly)
        Button {
            options.unreadOnly.toggle()
        } label: {
            Label(content.title, systemImage: content.symbol)
        }
        .accessibilityLabel(content.accessibilityLabel)
        .accessibilityAddTraits(options.unreadOnly ? .isSelected : [])
    }

    /// What the button shows for a state: pure, so a test reads it.
    struct Content: Equatable {
        /// « Non lus » or « Tous »: the list currently shown.
        let title: String
        /// The filter icon, filled while « Non lus » is on.
        let symbol: String
        /// « Afficher : non lus » or « Afficher : tous »: what the list shows now.
        let accessibilityLabel: String

        /// The content for the current choice.
        static func make(unreadOnly: Bool) -> Content {
            unreadOnly
                ? Content(title: "Non lus", symbol: "line.3.horizontal.decrease.circle.fill", accessibilityLabel: "Afficher : non lus")
                : Content(title: "Tous", symbol: "line.3.horizontal.decrease.circle", accessibilityLabel: "Afficher : tous")
        }
    }
}
