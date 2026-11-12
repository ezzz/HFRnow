import Observation
import SwiftUI
import UIKit

/// Whether a list or the reader is scrolling anywhere in the app: falling snow pauses meanwhile, so a scroll never shares its
/// frames with the snow (THEMES.md §4 rule 8, LESSONS 49).
@MainActor
@Observable
final class SeasonalScrollActivity {
    /// The app's one instance: SwiftUI lists report through `.seasonalScrollTracking()`, the reader's web view through `track`.
    static let shared = SeasonalScrollActivity()

    /// The scroll views moving now (dragged or decelerating).
    private(set) var moving: Set<ObjectIdentifier> = []
    @ObservationIgnored private var watchers: [ObjectIdentifier: PanWatcher] = [:]

    /// Something scrolls.
    var isScrolling: Bool { !moving.isEmpty }

    /// `source` started or stopped scrolling.
    func set(_ source: ObjectIdentifier, scrolling: Bool) {
        if scrolling {
            moving.insert(source)
        } else {
            moving.remove(source)
        }
    }

    /// Follows a UIKit scroll view (the reader's `WKWebView`) without taking its delegate: its pan gesture says when a drag
    /// starts, and its deceleration is followed until it stops.
    func track(_ scrollView: UIScrollView) {
        // Watchers of scroll views that went away are dropped; an address reused by a new scroll view gets a new watcher.
        watchers = watchers.filter { $0.value.scrollView != nil }
        let key = ObjectIdentifier(scrollView)
        guard watchers[key]?.scrollView !== scrollView else { return }
        let watcher = PanWatcher(scrollView: scrollView, activity: self)
        watchers[key] = watcher
        scrollView.panGestureRecognizer.addTarget(watcher, action: #selector(PanWatcher.panned(_:)))
    }

    /// Reports the drag and the deceleration of one scroll view.
    @MainActor
    private final class PanWatcher: NSObject {
        weak var scrollView: UIScrollView?
        weak var activity: SeasonalScrollActivity?
        let key: ObjectIdentifier

        init(scrollView: UIScrollView, activity: SeasonalScrollActivity) {
            self.scrollView = scrollView
            self.activity = activity
            key = ObjectIdentifier(scrollView)
        }

        @objc func panned(_ recognizer: UIPanGestureRecognizer) {
            switch recognizer.state {
            case .began, .changed:
                activity?.set(key, scrolling: true)
            default:
                Task { @MainActor [weak self] in await self?.settle() }
            }
        }

        /// Waits for the deceleration to end, checking ten times a second only while it lasts.
        private func settle() async {
            while scrollView?.isDecelerating == true, scrollView?.isTracking == false {
                try? await Task.sleep(for: .milliseconds(100))
            }
            if scrollView?.isTracking != true { activity?.set(key, scrolling: false) }
        }
    }
}

extension View {
    /// Reports this view's scroll view to `SeasonalScrollActivity.shared`, so the snow pauses while it scrolls (LOT-166).
    func seasonalScrollTracking() -> some View {
        modifier(SeasonalScrollTracking())
    }
}

private struct SeasonalScrollTracking: ViewModifier {
    /// A stable identity for this view's scroll view.
    @State private var token = Token()

    final class Token {}

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, phase in
                SeasonalScrollActivity.shared.set(ObjectIdentifier(token), scrolling: phase.isScrolling)
            }
            .onDisappear { SeasonalScrollActivity.shared.set(ObjectIdentifier(token), scrolling: false) }
    }
}
