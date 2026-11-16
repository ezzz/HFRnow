import CoreGraphics

/// The gap between a floating control and what it sits next to, one value for the app (operator decision of 2026-11-16 on
/// #820): the reader's page ends this far above its floating bottom bar, and the floating composer (#895) keeps this gap to
/// the keyboard and to the sides. The reference is the Claude iOS app's composer, about 8 points from the keyboard.
enum FloatingSpacing {
    /// The gap, in points (CSS pixels in the reader's page at zoom 1).
    static let gap: CGFloat = 8
}
