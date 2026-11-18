import SwiftUI

/// The rule of a pull to refresh from either end of a page (#1207): the refresh icon grows with the pull, the refresh fires once
/// when it reaches full size (with one haptic), and a release before that does nothing. Pure: the lists feed it from
/// `onScrollGeometryChange`, the reader from `ReaderPullWatcher`, so both ends of every screen follow one rule.
///
/// Legacy @ 87fe0d1c has only the system pull at the top of a list (`.refreshable`: `MainWindow.swift:791`, `Favorites.swift:747`,
/// `MPListView.swift:625`) and a bottom button in the reader (`MessagesView.swift:5051-5058`); this is SwiftHFR's own interaction
/// (operator, 2026-11-18).
struct PullRefreshRule: Equatable, Sendable {
    /// How far past the end, in points, the icon is at full size: the reader's threshold since #820.
    static let threshold: CGFloat = 72

    /// The icon's scale for a pull of `distance` points: 0 at rest, growing linearly, 1 from `threshold` on.
    static func scale(forPull distance: CGFloat) -> CGFloat {
        min(max(distance, 0) / threshold, 1)
    }

    /// Whether the current pull may still fire; set again by the next rest.
    private var isArmed = true

    /// Creates a rule at rest.
    init() {}

    /// Feeds the pull distance now; true exactly when this step reaches full size for the first time since the last rest (the
    /// caller then gives the haptic and refreshes). A rest (no pull, or scrolled back into the content) arms the next pull; a
    /// dip below the threshold without a rest does not, so one pull never refreshes twice.
    mutating func update(pull distance: CGFloat) -> Bool {
        if distance <= 0 {
            isArmed = true
            return false
        }
        guard isArmed, distance >= Self.threshold else { return false }
        isArmed = false
        return true
    }
}
