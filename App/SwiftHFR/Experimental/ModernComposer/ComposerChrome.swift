import CoreGraphics
import SwiftUI

/// Where the composer's controls sit (#854, operator 2026-11-12, reference: the Claude app's composer): on an iPhone the control
/// row inside the text card's bottom edge, and close, drafts and send as small floating glass buttons; an iPad keeps legacy's
/// bar and the row under the card, and so does an iPhone with Réglages › Expérimental › « Composer moderne » off (#903).
enum ComposerChrome: Equatable {
    /// An iPhone: the lighter composer docked on the keyboard.
    case docked
    /// An iPad, or an iPhone with the modern composer off: legacy's top bar and control row.
    case sheet

    /// `isPhone`: the composer is the modern one (`ModernComposer.isActive`: an iPhone with the option on).
    init(isPhone: Bool) { self = isPhone ? .docked : .sheet }

    /// The control row sits inside the text card, on its bottom edge.
    var controlsInCard: Bool { self == .docked }
    /// Close, drafts and send are small floating buttons instead of legacy's bar.
    var headerFloats: Bool { self == .docked }
}

/// The modern composer's margins (#895, operator 2026-11-14, reference: the Claude iOS app's composer, thin margins): one
/// shared gap, `FloatingSpacing.gap` (operator decision of 2026-11-16 on #820 and #895, about 8 pt, the gap between the Claude
/// app's card and the keyboard), between the floating buttons and the screen's sides, between them and the text card, at the
/// card's sides and under it down to the keyboard. A floating button's capsule is drawn smaller than its 44 pt hit area: the
/// hit area's slack counts toward the gap, so what the eye sees is the gap, and the hit area stays 44 pt. The legacy chrome (an
/// iPad, or the option off) keeps the paddings it had.
extension ComposerChrome {
    /// Around the text card: the gap at its sides and under it, nothing above (the floating buttons' bottom inset is the gap).
    var cardInsets: EdgeInsets {
        switch self {
        case .docked:
            EdgeInsets(top: 0, leading: FloatingSpacing.gap, bottom: FloatingSpacing.gap, trailing: FloatingSpacing.gap)
        case .sheet:
            EdgeInsets(top: ComposerCardLayout.gap, leading: 16, bottom: ComposerCardLayout.gap, trailing: 16)
        }
    }

    /// Around the composer's top bar, for a glyph of `glyph` points (`ComposerBarMetrics.glyphSize`): floating, each capsule is
    /// the gap away from the sides, from the page above and from the card below. On the main actor, as `ComposerHeader`'s
    /// rules it reads.
    @MainActor
    func headerInsets(glyph: CGFloat) -> EdgeInsets {
        switch self {
        case .docked:
            let slack = ComposerHeader.hitSlack(glyph: glyph)
            let vertical = max(0, FloatingSpacing.gap - slack.height)
            let horizontal = max(0, FloatingSpacing.gap - slack.width)
            return EdgeInsets(top: vertical, leading: horizontal, bottom: vertical, trailing: horizontal)
        case .sheet:
            return EdgeInsets(top: 14, leading: 16, bottom: 6, trailing: 16)
        }
    }
}

/// How the text card's tools are drawn (#895 D, operator 2026-11-14: "to try", as the Claude app's `+` and mic in round chips):
/// bare glyphs on the card's glass, or each glyph in its own round chip. The operator chooses on the device and the choice is
/// recorded on the PR; the other variant is then deleted. The chip is a plain fill, not glass: glass is not stacked on the
/// card's glass.
enum ComposerToolStyle: Equatable {
    case plain
    case pills

    /// The variant this build shows.
    static let current: ComposerToolStyle = .pills

    /// Space between a chip and its cell's edge: neighbouring chips never touch, the whole cell stays the hit area.
    static let chipInset: CGFloat = 4

    /// A chip's diameter in a cell of `cell` points.
    static func chipDiameter(cell: CGFloat) -> CGFloat { max(0, cell - 2 * chipInset) }
}
