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
    /// How far past the end, in points, the icon is full and the refresh fires: the one threshold of `PullRefreshRule`.
    static let threshold: CGFloat = PullRefreshRule.threshold

    /// Only a finger on the page starts a refresh; tests turn this off to move the offset without one.
    var requiresFinger = true

    private weak var scrollView: UIScrollView?
    private var observation: NSKeyValueObservation?
    private var rule = PullRefreshRule()
    private var progress: @MainActor (CGFloat) -> Void = { _ in }
    private var pulled: @MainActor () -> Void = {}

    /// Follows `scrollView`: `progress` gets the icon's scale (0 to 1) at each move, `pulled` is called once per pull.
    func track(
        _ scrollView: UIScrollView, progress: @escaping @MainActor (CGFloat) -> Void = { _ in },
        pulled: @escaping @MainActor () -> Void
    ) {
        self.scrollView = scrollView
        self.progress = progress
        self.pulled = pulled
        observation = scrollView.observe(\.contentOffset, options: []) { [weak self] scrollView, _ in
            MainActor.assumeIsolated { self?.offsetChanged(of: scrollView) }
        }
    }

    /// How far past the end `scrollView` is pulled, in points (zero or less when it is not).
    static func pull(of scrollView: UIScrollView) -> CGFloat {
        ReaderScrollGeometry.pastEnd(
            offsetY: scrollView.contentOffset.y, viewportHeight: scrollView.bounds.height,
            contentHeight: scrollView.contentSize.height, insetTop: scrollView.adjustedContentInset.top,
            insetBottom: scrollView.adjustedContentInset.bottom
        )
    }

    /// The scroll view moved. Internal so a test can drive it without a finger (`requiresFinger = false`).
    func offsetChanged(of scrollView: UIScrollView) {
        let held = !requiresFinger || scrollView.isTracking || scrollView.isDragging
        let pull = held ? Self.pull(of: scrollView) : 0
        progress(PullRefreshRule.scale(forPull: pull))
        if rule.update(pull: pull) { pulled() }
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
        controller.events.pullProgress = { [weak model] scale, token in
            guard let model, token == model.document?.token else { return }
            model.pullProgress = scale
        }
        controller.events.pulled = { [weak controller, weak model] token in
            guard let model, token == model.document?.token, !model.isLoading else { return }
            // Legacy `AppHaptics.refreshStarted()` (`Common.swift:108-110` @ 87fe0d1c): a light impact, then the refresh.
            haptic()
            Task { [controller] in await run(model: model, controller: controller) }
        }
    }
}
