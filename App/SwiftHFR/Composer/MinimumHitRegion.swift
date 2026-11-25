import SwiftUI

extension View {
    /// A hit region of at least 44 x 44 pt (HIG, Buttons) around a small control, whatever its glyph's size (#1156): the
    /// frame is the region (`contentShape` makes its transparent margin take taps). A caller that must keep its row's layout
    /// pulls the margin back with a negative padding of `MinimumHitRegion.overhang(of:)`: the region then overflows its
    /// neighbours.
    func minimumHitRegion() -> some View {
        frame(minWidth: ComposerHeader.hitSize, minHeight: ComposerHeader.hitSize).contentShape(.rect)
    }
}

enum MinimumHitRegion {
    /// How far `minimumHitRegion()` reaches past a glyph of `side` points, each side (0 for a glyph of 44 pt or more).
    static func overhang(of side: CGFloat) -> CGFloat { max(0, ComposerHeader.hitSize - side) / 2 }
}
