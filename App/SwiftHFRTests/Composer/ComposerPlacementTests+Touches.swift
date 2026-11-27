import UIKit

// Where touches land around the docked bar (#853), apart so the suite's file stays readable (#1194).
extension ComposerPlacementTests {
    /// The bar's top as touches see it: the first point above `textView` where the page takes the touch.
    static func barTop(in window: UIWindow, above textView: UITextView) -> CGFloat {
        let x = window.bounds.midX
        var top = textView.convert(textView.bounds, to: window).minY
        while top > 0, !isInScrollView(window.hitTest(CGPoint(x: x, y: top - 1), with: nil)) { top -= 1 }
        return top
    }

    /// Whether `view` is in the page's scroll view (the editor's own text view does not count).
    static func isInScrollView(_ view: UIView?) -> Bool {
        var current = view
        while let candidate = current {
            if candidate is UIScrollView, !(candidate is UITextView) { return true }
            current = candidate.superview
        }
        return false
    }
}
