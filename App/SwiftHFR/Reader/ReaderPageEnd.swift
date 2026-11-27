import SwiftUI
import UIKit

// Port of HFRswift/Swift/MessagesView.swift (`refreshCurrentPagePreservingScroll` :5051-5058 and `AppHaptics.refreshStarted`,
// Common.swift:108-110) @ 87fe0d1c. Differences: legacy refreshed from its bottom button only; the pull past the end is SwiftHFR's
// (operator, #820, 2026-11-15), and since #1207 it grows an icon and refreshes when the icon is full, not on release.
/// A pull past the end of the page: the distance feeds `PullRefreshRule` (the same rule as the lists), so the icon grows with the
/// pull and the refresh fires once, when it reaches full size (`threshold`). Only a finger pulls: a fling that overshoots the end
/// is not a refresh. The scroll view's offset is observed without taking its delegate, which belongs to WebKit (as
/// `SeasonalScrollActivity` does).
@MainActor
final class ReaderPullWatcher: NSObject {
    /// How far past an end, in points, the icon is full and the refresh fires: the one threshold of `PullRefreshRule`.
    static let threshold: CGFloat = PullRefreshRule.threshold

    /// Whether a finger is on `scrollView`; tests replace it to move the offset without one.
    var isFingerDown: (UIScrollView) -> Bool = { $0.isTracking || $0.isDragging }

    private weak var scrollView: UIScrollView?
    private var observation: NSKeyValueObservation?
    private var tracker = PullEdgesTracker()
    private var progress: @MainActor (_ top: CGFloat, _ bottom: CGFloat) -> Void = { _, _ in }
    private var pulled: @MainActor (_ edge: PullEdge) -> Void = { _ in }

    /// Follows `scrollView`: `progress` gets both icons' scales (0 to 1) at each move, `pulled` is called once per pull, with the end.
    func track(
        _ scrollView: UIScrollView, progress: @escaping @MainActor (_ top: CGFloat, _ bottom: CGFloat) -> Void = { _, _ in },
        pulled: @escaping @MainActor (_ edge: PullEdge) -> Void
    ) {
        self.scrollView = scrollView
        self.progress = progress
        self.pulled = pulled
        observation = scrollView.observe(\.contentOffset, options: []) { [weak self] scrollView, _ in
            MainActor.assumeIsolated { self?.offsetChanged(of: scrollView) }
        }
        // A lift with no momentum moves no offset: the pan's end arms the next touch.
        scrollView.panGestureRecognizer.addTarget(self, action: #selector(panChanged(_:)))
    }

    @objc private func panChanged(_ pan: UIPanGestureRecognizer) {
        if pan.state == .ended || pan.state == .cancelled || pan.state == .failed { fingerLifted() }
    }

    /// The finger left the page: the icons go and the next touch may refresh. Internal so a test can lift without a gesture.
    func fingerLifted() {
        tracker.fingerLifted()
        progress(0, 0)
    }

    /// How far past the end `scrollView` is pulled, in points (zero or less when it is not).
    static func pull(of scrollView: UIScrollView) -> CGFloat {
        ReaderScrollGeometry.pastEnd(
            offsetY: scrollView.contentOffset.y, viewportHeight: scrollView.bounds.height,
            contentHeight: scrollView.contentSize.height, insetTop: scrollView.adjustedContentInset.top,
            insetBottom: scrollView.adjustedContentInset.bottom
        )
    }

    /// How far past the top `scrollView` is pulled, in points (zero or less when it is not).
    static func topPull(of scrollView: UIScrollView) -> CGFloat {
        -(scrollView.contentOffset.y + scrollView.adjustedContentInset.top)
    }

    /// The scroll view moved. Internal so a test can drive it without a finger (`isFingerDown`).
    func offsetChanged(of scrollView: UIScrollView) {
        let step = tracker.update(
            topPull: Self.topPull(of: scrollView), bottomPull: Self.pull(of: scrollView), fingerDown: isFingerDown(scrollView)
        )
        progress(step.top, step.bottom)
        if let edge = step.firedEdge { pulled(edge) }
    }
}

/// The reader's one refresh and the end of the page (#820).
@MainActor
enum ReaderRefresh {
    /// The refresh behind the top bar's button, the end-of-page button and the pull past the end: one code path.
    ///
    /// Legacy plays a light impact when a refresh starts and another when it completes, loaded or failed
    /// (`AppHaptics.refreshStarted` / `refreshCompleted`, `MessagesView.swift:5051-5053, 5153-5157` @ 87fe0d1c). A refresh the
    /// model refuses (a composer is open) is silent, and `startsWithHaptic: false` is for the pull, which played its own.
    static func run(
        model: TopicReaderModel, controller: ReaderWebController?, startsWithHaptic: Bool = true,
        haptic: @escaping @MainActor () -> Void = { HapticFeedback.live.impact(.light) }
    ) async {
        let refuses = model.suspendsPageInteractions
        if startsWithHaptic, !refuses { haptic() }
        controller?.resume()
        await model.refresh()
        if !refuses { haptic() }
    }

    /// Follows the end of the page `controller` shows into `atPageEnd`, and turns a pull past it into a refresh. Reports of
    /// another document than the model's (a late one) change nothing.
    static func wirePageEnd(
        of controller: ReaderWebController, model: TopicReaderModel, atPageEnd: Binding<Bool>,
        haptic: @escaping @MainActor () -> Void = { HapticFeedback.live.impact(.light) }
    ) {
        controller.events.pageEnd = { [weak model] atEnd, token in
            guard let model, token == model.document?.token else { return }
            // Legacy animates the bar's change (`.animation(.easeOut(duration: 0.22))`, MessagesView.swift:5789 @ 87fe0d1c).
            withAnimation(.easeOut(duration: 0.22)) { atPageEnd.wrappedValue = atEnd }
        }
        controller.events.pullProgress = { [weak model] top, bottom, token in
            guard let model, token == model.document?.token else { return }
            model.pullTop = top
            model.pullBottom = bottom
        }
        controller.events.pulled = { [weak controller, weak model] edge, token in
            guard let model, token == model.document?.token, !model.isLoading else { return }
            // Legacy `AppHaptics.refreshStarted()` (`Common.swift:108-110` @ 87fe0d1c): a light impact, then the refresh.
            haptic()
            model.pulledEdge = edge
            Task { [controller] in
                await run(model: model, controller: controller, startsWithHaptic: false, haptic: haptic)
                model.pulledEdge = nil
            }
        }
    }
}
