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

    /// #1073 item 4 (operator, 2026-11-17: a solid accent fill is « un gros bloc de couleur »): the background of a row a list
    /// can select. A selected row is a light accent tint, twice a state pill's strength (`selectedStrength`) so it stays the
    /// strongest mark of the row, and the pill of a super favourite, a flag or an unread MP still shows over it. Nil on an
    /// unselected classic row keeps the card's own background; the dense look's clear row stays clear. Legacy's split-view
    /// topic row is a solid `actionTintColor` rounded rectangle with white text (`Common.swift:3669-3676`, `:3372-3392` @ 87fe0d1c),
    /// so the light tint is the operator's decision, not a port.
    func rowBackground(isSelected: Bool, scheme: ColorScheme, contrast: ColorSchemeContrast) -> Color? {
        if isSelected { return Color.accentColor.opacity(Self.selectedStrength(scheme: scheme, contrast: contrast)) }
        return self == .dense ? DenseListLook.rowBackground : nil
    }

    /// Opacity of the selected row's tint: twice `RowTint.strength`, in light and dark and with Increase Contrast.
    static func selectedStrength(scheme: ColorScheme, contrast: ColorSchemeContrast) -> Double {
        RowTint.strength(scheme: scheme, contrast: contrast) * 2
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
    @Environment(\.screenPaintsLists) private var painted

    func body(content: Content) -> some View {
        let look = ListLook.current(experimental)
        // EXPERIMENTAL(denseRows, #1107): the dense look replaces the grouped background by the plain list's, unless a theme or
        // a dark style already paints the screen behind the list. The classic value is the one `AppScreenBackground` set (hidden
        // where it paints, the system's elsewhere), so the classic look is unchanged.
        let hidesBackground = painted || look == .dense
        content
            .listStyle(.insetGrouped)
            .scrollContentBackground(hidesBackground ? .hidden : .automatic)
            .background(look == .dense && !painted ? DenseListLook.plainBackground : Color.clear)
            .densityListMargins()
            .environment(\.listLook, look)
    }
}

/// The background of the rows: the card's (nil, the system's) in the classic look.
private struct ListLookRows: ViewModifier {
    @Environment(\.listLook) private var look
    @Environment(\.themeAppearance) private var appearance

    @ViewBuilder func body(content: Content) -> some View {
        if appearance.listColors != nil {
            // #842: a gallery theme's rows, in this look (`themedListRow`).
            content.themedListRow()
        } else {
            // EXPERIMENTAL(denseRows, #1107): the dense look's clear row replaces the card's background.
            content.listRowBackground(look == .dense ? DenseListLook.rowBackground : nil)
        }
    }
}

/// The background of a row a list can select: both looks draw a light tint (`ListLook.rowBackground`). The dense look's clear
/// row would hide the list's selection, and the classic look's system fill is solid.
private struct ListLookRow: ViewModifier {
    let isSelected: Bool
    @Environment(\.listLook) private var look
    @Environment(\.themeAppearance) private var appearance
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    @ViewBuilder func body(content: Content) -> some View {
        if appearance.listColors != nil {
            // #842: a gallery theme's row and selection, in this look (`themedListRow`).
            content.themedListRow(isSelected: isSelected)
        } else {
            // EXPERIMENTAL(denseRows, #1107): the dense look's clear or selected row replaces the card's background.
            // #1073: the classic look no longer leaves the system's solid accent fill on the selected row (iPad split).
            content.listRowBackground(look.rowBackground(isSelected: isSelected, scheme: scheme, contrast: contrast))
        }
    }
}

extension View {
    /// The look of a list (#1107): the inset-grouped style, its margins, and the look its rows and headers read. Every list of
    /// #572's definition sets it instead of its own style.
    func listLook() -> some View { modifier(ListLookModifier()) }

    /// The rows' background in the list's look: put it once around the whole content of the list (`List { Group { … }
    /// .listLookRows() }`), so no row keeps the card in the dense look. A row's own `listRowBackground` (a selected row's accent)
    /// wins over it.
    func listLookRows() -> some View { modifier(ListLookRows()) }

    /// The background of a row of a list with a selection (Catégories, the topic lists, Messages): the selected row keeps a
    /// highlight in the dense look (#1107, iPad columns).
    func listLookRow(isSelected: Bool) -> some View { modifier(ListLookRow(isSelected: isSelected)) }
}
