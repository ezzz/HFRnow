import SwiftUI

// Port of HFRswift/Swift/Common.swift (TopicListRowView `rowBackgroundTint`, :3677-3684 @ 87fe0d1c): a highlighted row is a rounded
// tinted pill (corner 12, continuous) drawn behind the row, overflowing its content by `rowBackgroundOverflow`, inset inside the
// list's block. Differences: the tint is a few percent of the accent over the block, not a palette colour (#570); the overflow is
// capped by the row insets of the density (#803).
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

    /// How far the pill reaches past the row's content: legacy's `rowBackgroundOverflow`, a little more on top for the super
    /// favourite (`Favorites.swift:1136-1138`, `MainWindow.swift:738-740` @ 87fe0d1c; the MP list has no tint in legacy).
    static func overflow(isSuperFavorite: Bool) -> EdgeInsets {
        EdgeInsets(top: isSuperFavorite ? 4 : 2, leading: 8, bottom: 2, trailing: 8)
    }

    /// `overflow` never past the row's own insets, so a compact row's pill stays inside the block.
    static func capped(_ overflow: EdgeInsets, by insets: EdgeInsets) -> EdgeInsets {
        EdgeInsets(
            top: min(overflow.top, insets.top), leading: min(overflow.leading, insets.leading),
            bottom: min(overflow.bottom, insets.bottom), trailing: min(overflow.trailing, insets.trailing)
        )
    }
}

private struct RowPill: ViewModifier {
    let tint: RowTint?
    let overflow: EdgeInsets
    @Environment(\.listDensity) private var density

    func body(content: Content) -> some View {
        content.background {
            if let tint {
                let edge = RowTint.capped(overflow, by: density.rowInsets)
                tint.padding(.top, -edge.top).padding(.leading, -edge.leading)
                    .padding(.bottom, -edge.bottom).padding(.trailing, -edge.trailing)
            }
        }
    }
}

extension View {
    /// Draws a row's highlight as legacy does: a rounded pill behind the row, inset inside the list's block; nil draws nothing.
    func rowPill(_ tint: RowTint?, overflow: EdgeInsets = RowTint.overflow(isSuperFavorite: false)) -> some View {
        modifier(RowPill(tint: tint, overflow: overflow))
    }
}
