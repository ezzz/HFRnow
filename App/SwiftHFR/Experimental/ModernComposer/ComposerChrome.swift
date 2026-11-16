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
