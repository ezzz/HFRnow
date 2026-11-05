import CoreGraphics

// Port of HFRswift/Swift/MessagesView.swift (the topic view's `DragGesture`, `master` @21173e7 lines 5295-5320; the key is
// absent from 2440d79). Differences: the decision is a pure function; legacy skipped the swipe while a text selection was
// active (`isMessageTextInteractionActive`) and in its post filter mode, neither exists in this reader yet (GAP-071, M5).

/// The page change a horizontal drag asks for.
enum PageSwipe: Equatable, Sendable {
    /// Drag towards the left: the next page, shown from its top.
    case next
    /// Drag towards the right: the previous page, shown from its end.
    case previous

    /// Legacy thresholds (hard-coded there): at least 120 pt of horizontal travel, 70 pt of horizontal impulse after the
    /// finger lifts in the same direction, and a vertical travel below half the horizontal one.
    static let minimumDistance: CGFloat = 120
    /// Minimum predicted extra travel after the finger lifts.
    static let minimumImpulse: CGFloat = 70
    /// Largest vertical / horizontal travel ratio.
    static let maximumVerticalRatio: CGFloat = 0.5

    /// What a drag that ended at `translation`, predicted to stop at `predictedEnd`, asks for; nil for a drag that is not a
    /// page swipe or has no page to go to (`page` is 1-based).
    static func of(translation: CGSize, predictedEnd: CGSize, page: Int, maxPage: Int) -> PageSwipe? {
        let horizontal = translation.width
        let vertical = translation.height
        let impulse = predictedEnd.width - horizontal
        guard abs(horizontal) > minimumDistance, abs(impulse) > minimumImpulse,
              (horizontal < 0) == (impulse < 0), abs(vertical) < abs(horizontal) * maximumVerticalRatio
        else { return nil }
        if horizontal < 0 { return page < maxPage ? .next : nil }
        return page > 1 ? .previous : nil
    }
}
