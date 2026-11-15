/// The modern composer (#904, behind Réglages › Expérimental › « Composer moderne », #903): on an iPhone, the compact card
/// docked on the keyboard that grows with its text (#653, `ComposerHeight`, `ComposerCardLayout`), the controls inside the card
/// and small floating buttons (#888, `ComposerChrome`). Off, the composer shows at full height with legacy's bar and row, as
/// on an iPad; #855 builds the legacy full-screen cover on that side and flips the switch's default.
///
/// This folder holds the option's own code; `ReplyComposerView` picks it at the `EXPERIMENTAL(modernComposer, #904)` marker.
enum ModernComposer {
    /// Whether the composer is the modern one: an iPhone with the option on. An iPad never is.
    static func isActive(isPhone: Bool, isOn: Bool) -> Bool { isPhone && isOn }
}
