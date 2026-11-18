import SwiftUI

// #1107 (operator, 2026-11-18): one look for every list (#572's definition), driven by the switch that draws the rows, so a list
// never mixes the two. Legacy draws its lists with no explicit style on its palette (`Favorites.swift:666`, `MainWindow.swift:663`
// @ 87fe0d1c); the classic look is #803's rounded block per section, the Favoris card.
/// The look of every list: the Favoris card (default) or, behind Réglages › Expérimental › « Lignes denses », the dense look.
enum ListLook: Sendable, Equatable {
    /// One rounded grey card per section, the system's wide side margins (the Favoris look, #803).
    case classic
    /// Rows on the screen's background, side to side, with no card: the dense view (#1107, `DenseListLook`).
    case dense

    /// EXPERIMENTAL(denseRows, #1107): the switch point, the same flag as the rows (`TopicRowStyle.current`); off (or no settings
    /// in the environment), the classic look.
    @MainActor static func current(_ experimental: ExperimentalSettings?) -> ListLook {
        DenseRowFormat.isOn(experimental) ? .dense : .classic
    }

    /// Outer side margin of the list, from the safe-area edge to the card: nil keeps the system's (or the density's), a value
    /// replaces it.
    func outerMargin(_ density: ListDensity) -> CGFloat? {
        switch self {
        case .classic: density.outerMargin
        // EXPERIMENTAL(denseRows, #1107): replaces the card's margin.
        case .dense: DenseListLook.outerMargin
        }
    }

    /// The inner side inset of a row that keeps the system's vertical insets, and of the section headers: nil keeps the system's.
    func rowSideInset(_ density: ListDensity) -> CGFloat? {
        outerMargin(density) == nil ? nil : density.rowInsets.leading
    }
}

extension EnvironmentValues {
    /// The look of the enclosing list, set by `listLook()`.
    @Entry var listLook = ListLook.classic
}

/// Sets the list's style and margins from the look. The style never changes, and the margins and row backgrounds are values (nil
/// for the system's), so switching the look keeps the list's identity: no reload, no lost scroll position (#1107).
private struct ListLookModifier: ViewModifier {
    @Environment(ExperimentalSettings.self) private var experimental: ExperimentalSettings?

    func body(content: Content) -> some View {
        content
            .listStyle(.insetGrouped)
            .densityListMargins()
            .environment(\.listLook, ListLook.current(experimental))
    }
}

/// The background of the rows: the card's (nil, the system's) in the classic look.
private struct ListLookRows: ViewModifier {
    @Environment(\.listLook) private var look

    func body(content: Content) -> some View {
        content.listRowBackground(look == .dense ? DenseListLook.rowBackground : nil)
    }
}

extension View {
    /// The look of a list (#1107): the inset-grouped style, its margins, and the look its rows and headers read. Every list of
    /// #572's definition sets it instead of its own style.
    func listLook() -> some View { modifier(ListLookModifier()) }

    /// The rows' background in the list's look: put it on the rows (a `ForEach`, a section's content), not on the list. A row's
    /// own `listRowBackground` (a clear title row, a selected bookmark) wins over it.
    func listLookRows() -> some View { modifier(ListLookRows()) }
}
