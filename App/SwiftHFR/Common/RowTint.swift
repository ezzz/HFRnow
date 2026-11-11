import SwiftUI

// Port of HFRswift/Swift/Common.swift (TopicListRowView `rowBackgroundTint`, :3677-3684 @ 87fe0d1c): a highlighted row is a rounded
// tinted pill (corner 12, continuous) drawn behind the row, overflowing its content by `rowBackgroundOverflow`, inset inside the
// list's block. Differences: the tint is a few percent of the accent over the block, not a palette colour (#570); the pill is
// placed from the cell edge, where Swift's row insets hold what legacy's `contentPadding` does (#803).
/// A state tint for a list row: a few percent of `tint` over the block, as a rounded pill (#570, #803).
struct RowTint: View {
    var tint: Color = .accentColor
    /// Multiplies the strength, for a quieter tint.
    var weight = 1.0
    @Environment(\.colorScheme) private var scheme
    @Environment(\.colorSchemeContrast) private var contrast

    var body: some View {
        RoundedRectangle(cornerRadius: Self.cornerRadius, style: .continuous)
            .fill(tint.opacity(Self.strength(scheme: scheme, contrast: contrast, weight: weight)))
    }

    /// Legacy's pill corner radius (`Common.swift:3678` @ 87fe0d1c).
    static let cornerRadius: CGFloat = 12

    /// Opacity of the tint: stronger in dark, where the same alpha reads weaker, and again with Increase Contrast.
    static func strength(scheme: ColorScheme, contrast: ColorSchemeContrast, weight: Double = 1) -> Double {
        ((scheme == .dark ? 0.16 : 0.10) + (contrast == .increased ? 0.08 : 0)) * weight
    }

    /// Legacy's gap between the pill and the block edge, side to side: the row's inset minus the horizontal overflow, 12 - 8
    /// (`MainWindow.swift:738-740, 771` @ 87fe0d1c).
    static let edgeGap: CGFloat = 4

    /// How far the pill reaches past the row's content, measured from the cell edge as legacy measures it: legacy's overflow sits
    /// on top of its `contentPadding` (`Common.swift:3668`, `Favorites.swift:1135` 2/6/2/0, `MainWindow.swift:737` 2/0/2/0), which
    /// Swift keeps in `rowInsets`. So the pill stops `edgeGap` short of the block edge, and reaches 4 pt above and below a
    /// flagged row's content, 6 above a super favourite's (`contentPadding` 2 + overflow 4, `Favorites.swift:1135-1138`), never
    /// past the cell. The MP list has no tint in legacy: its pill takes the flagged-row values.
    static func overflow(isSuperFavorite: Bool, insets: EdgeInsets) -> EdgeInsets {
        EdgeInsets(
            top: min(isSuperFavorite ? 6 : 4, insets.top), leading: max(0, insets.leading - edgeGap),
            bottom: min(4, insets.bottom), trailing: max(0, insets.trailing - edgeGap)
        )
    }
}

private struct RowPill: ViewModifier {
    let tint: RowTint?
    let isSuperFavorite: Bool
    @Environment(\.listDensity) private var density

    func body(content: Content) -> some View {
        content.background {
            if let tint {
                let edge = RowTint.overflow(isSuperFavorite: isSuperFavorite, insets: density.rowInsets)
                tint.padding(.top, -edge.top).padding(.leading, -edge.leading)
                    .padding(.bottom, -edge.bottom).padding(.trailing, -edge.trailing)
            }
        }
    }
}

extension View {
    /// Draws a row's highlight as legacy does: a rounded pill behind the row, inset inside the list's block; nil draws nothing.
    func rowPill(_ tint: RowTint?, isSuperFavorite: Bool = false) -> some View {
        modifier(RowPill(tint: tint, isSuperFavorite: isSuperFavorite))
    }
}
