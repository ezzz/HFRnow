import SwiftUI

/// The spacing of a Réglages row that shows a description under its control (#1128): one value for the Expérimental options and
/// the MP storage row, so every title-to-description gap renders like « MP multiples → dark topic » did on dev-swift (operator,
/// 2026-11-18: that rendered gap is the reference).
enum SettingsRowSpacing {
    /// Between a switch's title and the description under it. 2 pt, not the 6 pt the options used: at 6 pt their rows rendered
    /// 4 pt above the reference. The switch-and-ⓘ `HStack` adds nothing, so the reference's 2 pt is the value
    /// (`SettingsRowSpacingRenderedTests` measures the pixels of each row against the reference).
    static let titleToDescription: CGFloat = 2
}
