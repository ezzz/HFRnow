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

    /// Whether the current touch may still fire: set again only once the finger is up.
    private var isArmed = true

    /// Creates a rule at rest.
    init() {}

    /// The finger left the page: the next touch may fire, even if no offset moved after the lift.
    mutating func fingerLifted() {
        isArmed = true
    }

    /// Feeds the pull distance now and whether a finger is on the page; true exactly when this step reaches full size with a
    /// finger down, the first time since the finger last left (the caller then gives the haptic and refreshes). Only a lifted finger
    /// arms the next pull: a refresh that resets the page to its top (WebKit, #642) is no rest while the finger is still down, so
    /// one touch never refreshes twice.
    mutating func update(pull distance: CGFloat, fingerDown: Bool) -> Bool {
        guard fingerDown else {
            isArmed = true
            return false
        }
        guard isArmed, distance >= Self.threshold else { return false }
        isArmed = false
        return true
    }
}

/// An end of a scrolling page.
enum PullEdge: Equatable, Sendable {
    case top, bottom
}

/// The two ends of a scrolling page (#1207): each has its own `PullRefreshRule`, and only a finger on the page pulls, so a fling
/// that overshoots an end grows no icon and refreshes nothing.
struct PullEdgesTracker: Equatable, Sendable {
    /// What one move of the list changes: both icons' scales (0 to 1), and whether the refresh fires now, from the top or the bottom.
    struct Step: Equatable, Sendable {
        var top: CGFloat
        var bottom: CGFloat
        var fires: Bool
        var firesAtTop: Bool

        /// The end that fires now, nil when none does.
        var firedEdge: PullEdge? { fires ? (firesAtTop ? .top : .bottom) : nil }
    }

    private var topRule = PullRefreshRule()
    private var bottomRule = PullRefreshRule()

    /// Creates a tracker at rest.
    init() {}

    /// The finger left the page: both ends may fire on the next touch.
    mutating func fingerLifted() {
        topRule.fingerLifted()
        bottomRule.fingerLifted()
    }

    /// Feeds the pulls past the top and the bottom, in points, and whether a finger is on the list.
    mutating func update(topPull: CGFloat, bottomPull: CGFloat, fingerDown: Bool) -> Step {
        let top = fingerDown ? topPull : 0
        let bottom = fingerDown ? bottomPull : 0
        let firesTop = topRule.update(pull: top, fingerDown: fingerDown)
        let firesBottom = bottomRule.update(pull: bottom, fingerDown: fingerDown)
        return Step(
            top: PullRefreshRule.scale(forPull: top), bottom: PullRefreshRule.scale(forPull: bottom),
            fires: firesTop || firesBottom, firesAtTop: firesTop
        )
    }
}
