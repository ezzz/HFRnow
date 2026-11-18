import SwiftUI

/// The spacing of a Réglages row that shows a description under its control (#1128): one value for the Expérimental options and
/// the MP storage row, which used 6 and 2 pt.
enum SettingsRowSpacing {
    /// Between a switch's title and the description under it. 8 pt: clearly more than the 2 and 6 pt it replaces; an estimate of
    /// Settings.app's look, not measured, to confirm on a device (#893).
    static let titleToDescription: CGFloat = 8
}
