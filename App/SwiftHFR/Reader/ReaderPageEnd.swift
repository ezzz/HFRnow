import SwiftUI
import UIKit

// Port of HFRswift/Swift/MessagesView.swift (`refreshCurrentPagePreservingScroll` :5051-5058 and `AppHaptics.refreshStarted`,
// Common.swift:108-110) @ 87fe0d1c. Differences: legacy refreshed from its bottom button only; the pull past the end and its hint
// are SwiftHFR's (operator, #820, 2026-11-15).
/// A pull past the end of the page, let go beyond `threshold`: a refresh. The scroll view's pan gesture is followed without
/// taking its delegate, which belongs to WebKit (as `SeasonalScrollActivity` does). The hint « Tirer vers le haut pour
/// actualiser » is a label under the page's end, in the scroll view: it shows only while the page is pulled past its end, so
/// it costs the page no room at rest (#820).
@MainActor
final class ReaderPullWatcher: NSObject {
    /// How far past the end, in points, a release refreshes. Shorter pulls do nothing.
    static let threshold: CGFloat = 72

    /// The hint under the page's end; added to the scroll view only once `showsHint` is set.
    let hint: UILabel = {
        let label = UILabel()
        label.text = "Tirer vers le haut pour actualiser"
        label.font = UIFont.preferredFont(forTextStyle: .footnote)
        label.adjustsFontForContentSizeCategory = true
        label.textColor = .secondaryLabel
        label.alpha = 0.75
        label.textAlignment = .center
        // VoiceOver has the "Actualiser" buttons; the hint is for the finger only.
        label.isAccessibilityElement = false
        return label
    }()

    /// Whether the hint is drawn: only a reader that refreshes on a pull (`ReaderRefresh.wirePageEnd`), not the post filter.
    var showsHint = false {
        didSet { if showsHint != oldValue { placeHint() } }
    }

    private weak var scrollView: UIScrollView?
    private var pulled: @MainActor () -> Void = {}
    private var observations: [NSKeyValueObservation] = []

    func track(_ scrollView: UIScrollView, pulled: @escaping @MainActor () -> Void) {
        self.scrollView = scrollView
        self.pulled = pulled
        scrollView.panGestureRecognizer.addTarget(self, action: #selector(panned(_:)))
        // The page's end moves with its content (images, a pinch zoom, a rotation that lays the page out again); never on a
        // mere scroll, which would place the label every frame.
        observations = [
            scrollView.observe(\.contentSize) { [weak self] _, _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.placeHint()
                }
            }
        ]
    }

    /// Puts the hint `FloatingSpacing.gap` below the end of the content, across the visible width; removes it when not shown.
    func placeHint() {
        guard showsHint, let scrollView else { return hint.removeFromSuperview() }
        if hint.superview !== scrollView { scrollView.addSubview(hint) }
        let height = hint.sizeThatFits(CGSize(width: scrollView.bounds.width, height: .greatestFiniteMagnitude)).height
        hint.frame = CGRect(
            x: 0, y: scrollView.contentSize.height + FloatingSpacing.gap,
            width: scrollView.bounds.width, height: ceil(height)
        )
    }

    /// Whether letting go of `scrollView` now refreshes. Internal so tests can check it without a finger.
    static func isPulledPastEnd(_ scrollView: UIScrollView) -> Bool {
        ReaderScrollGeometry.pastEnd(
            offsetY: scrollView.contentOffset.y, viewportHeight: scrollView.bounds.height,
            contentHeight: scrollView.contentSize.height, insetTop: scrollView.adjustedContentInset.top,
            insetBottom: scrollView.adjustedContentInset.bottom
        ) >= threshold
    }

    /// The pan gesture's action. Internal so a test can hand it a released gesture.
    @objc func panned(_ recognizer: UIPanGestureRecognizer) {
        // At `.ended` the offset is still the pulled one: the bounce back starts after.
        guard recognizer.state == .ended, let scrollView, Self.isPulledPastEnd(scrollView) else { return }
        pulled()
    }
}

/// The reader's one refresh and the end of the page (#820).
@MainActor
enum ReaderRefresh {
    /// The refresh behind the top bar's button, the end-of-page button and the pull past the end: one code path.
    static func run(model: TopicReaderModel, controller: ReaderWebController?) async {
        controller?.resume()
        await model.refresh()
    }

    /// Follows the end of the page `controller` shows into `atPageEnd`, turns a pull past it into a refresh, and shows the
    /// pull hint. Reports of another document than the model's (a late one) change nothing.
    static func wirePageEnd(
        of controller: ReaderWebController, model: TopicReaderModel, atPageEnd: Binding<Bool>,
        haptic: @escaping @MainActor () -> Void = { HapticFeedback.live.impact(.light) }
    ) {
        controller.pullWatcher.showsHint = true
        controller.events.pageEnd = { [weak model] atEnd, token in
            guard let model, token == model.document?.token else { return }
            // Legacy animates the bar's change (`.animation(.easeOut(duration: 0.22))`, MessagesView.swift:5789 @ 87fe0d1c).
            withAnimation(.easeOut(duration: 0.22)) { atPageEnd.wrappedValue = atEnd }
        }
        controller.events.pulled = { [weak controller, weak model] token in
            guard let model, token == model.document?.token, !model.isLoading else { return }
            // Legacy `AppHaptics.refreshStarted()` (`Common.swift:108-110` @ 87fe0d1c): a light impact, then the refresh.
            haptic()
            Task { [controller] in await run(model: model, controller: controller) }
        }
    }
}
