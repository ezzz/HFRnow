import HFRModels
import SwiftUI
import UIKit

// New in SwiftHFR (#1456, operator on device 2026-11-28): under a flat theme (Rétro 5250: `surface` is the page's black) the
// grouped sections of a list have no visible edge. The rows of a `ThemedSection` then draw one 1 pt outline that follows the
// section's shape in `groupOutline`; a theme whose card stands out from the page (`ThemeTokens.cardStandsOut`), Legacy, the dense
// look and a row outside a `ThemedSection` or `ThemedRows` (the iPad sidebar has no card) draw none.
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

/// Where a row sits in its section: a `List` row cannot tell, so `ThemedSection` says.
enum GroupRowPosition: Equatable {
    case only, first, middle, last

    init(index: Int, count: Int) {
        switch (index == 0, index == count - 1) {
        case (true, true): self = .only
        case (true, false): self = .first
        case (false, true): self = .last
        case (false, false): self = .middle
        }
    }
}

/// The part of the section's outline a row draws: the sides for every row, the top (and its corners) for the first, the bottom for
/// the last, so the strokes of a section join into one outline with no line between its rows. The sides run to the row's edge where
/// the section continues, so they have no gap at a row boundary; the line itself is inset half its width, horizontally only.
struct GroupOutlineShape: Shape {
    let position: GroupRowPosition
    /// The corner radius of the system's inset-grouped card, measured on the iOS 27.2 simulator (iPhone Duo).
    static let cornerRadius: CGFloat = 26

    func path(in rect: CGRect) -> Path {
        let top = position == .only || position == .first
        let bottom = position == .only || position == .last
        // A corner cannot be taller than its row: half of it when one row carries both corners (compact rows are 28 pt).
        let radius = min(Self.cornerRadius, position == .only ? rect.height / 2 : rect.height)
        let (left, right) = (rect.minX + 0.5, rect.maxX - 0.5)
        let (upper, lower) = (rect.minY + 0.5, rect.maxY - 0.5)
        var path = Path()
        path.move(to: CGPoint(x: left, y: bottom ? lower - radius : rect.maxY))
        path.addLine(to: CGPoint(x: left, y: top ? upper + radius : rect.minY))
        if top {
            path.addArc(
                center: CGPoint(x: left + radius, y: upper + radius), radius: radius,
                startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false
            )
            path.addLine(to: CGPoint(x: right - radius, y: upper))
            path.addArc(
                center: CGPoint(x: right - radius, y: upper + radius), radius: radius,
                startAngle: .degrees(270), endAngle: .degrees(360), clockwise: false
            )
        } else {
            path.move(to: CGPoint(x: right, y: rect.minY))
        }
        path.addLine(to: CGPoint(x: right, y: bottom ? lower - radius : rect.maxY))
        if bottom {
            path.addArc(
                center: CGPoint(x: right - radius, y: lower - radius), radius: radius,
                startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false
            )
            path.addLine(to: CGPoint(x: left + radius, y: lower))
            path.addArc(
                center: CGPoint(x: left + radius, y: lower - radius), radius: radius,
                startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false
            )
        }
        return path
    }
}

/// A themed row's fill with its part of the section's outline.
struct GroupOutlineRowBackground: View {
    let fill: Color
    let outline: Color
    let position: GroupRowPosition

    var body: some View {
        fill.overlay { GroupOutlineShape(position: position).stroke(outline, lineWidth: 1) }
    }
}
