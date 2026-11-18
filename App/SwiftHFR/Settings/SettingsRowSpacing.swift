import SwiftUI

/// The spacing of a Réglages row that shows a description under its control (#1128): one value for the Expérimental options and
/// the MP storage row, which used 6 and 2 pt (operator, 2026-11-18: 6 pt is the one to keep).
enum SettingsRowSpacing {
    /// Between a switch's title and the description under it: the Expérimental rows' 6 pt, which the operator chose to keep.
    static let titleToDescription: CGFloat = 6
}
