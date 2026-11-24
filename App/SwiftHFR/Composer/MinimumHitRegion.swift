import SwiftUI

extension View {
    /// A hit region of at least 44 x 44 pt (HIG, Buttons) around a small control, whatever its glyph's size (#1156): the
    /// frame is the region, so the look stays the same.
    func minimumHitRegion() -> some View {
        frame(minWidth: ComposerHeader.hitSize, minHeight: ComposerHeader.hitSize).contentShape(.rect)
    }
}
