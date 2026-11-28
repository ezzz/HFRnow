import HFRModels
import SwiftUI
import UIKit

// New in SwiftHFR (#1456, operator on device 2026-11-28): under a flat theme (Rétro 5250: `surface` is the page's black) the
// grouped sections of a list have no visible edge. A themed row then draws a 1 pt outline in `groupOutline`; a theme whose card
// stands out from the page (`ThemeTokens.cardStandsOut`) and Legacy draw none. One place, applied by `themedListRow`, so every
// grouped list follows (Réglages and its sub-screens, Comptes, Profil, À propos…).
extension ThemeAppearance {
    /// The outline of a grouped section, dynamic (light and dark), or nil for Legacy. Clear in a variant whose card stands out,
    /// so the decision is per appearance, as the tokens are.
    var groupOutlineColor: UIColor? {
        themeColor(\.drawnGroupOutline)
    }
}

extension ThemeTokens {
    /// `resolvedGroupOutline` when the card does not stand out from the page, else a clear colour (nothing is drawn).
    var drawnGroupOutline: ThemeRGB {
        cardStandsOut ? ThemeRGB(red: 0, green: 0, blue: 0, alpha: 0) : resolvedGroupOutline
    }
}

/// A themed row's fill with the group outline on its edges: the sides at 1 pt, the top and bottom at half a point because
/// the rows of a group stack, so two neighbours' edges add up to the 1 pt of the group's own top and bottom, which a row cannot
/// tell from an inner edge (a `List` row does not know whether it is the first or the last of its section).
struct GroupOutlineRowBackground: View {
    let fill: Color
    let outline: Color

    var body: some View {
        fill
            .overlay(alignment: .leading) { outline.frame(width: 1) }
            .overlay(alignment: .trailing) { outline.frame(width: 1) }
            .overlay(alignment: .top) { outline.frame(height: 0.5) }
            .overlay(alignment: .bottom) { outline.frame(height: 0.5) }
    }
}
