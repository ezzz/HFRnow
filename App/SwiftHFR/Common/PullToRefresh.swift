import SwiftUI

/// How far a list is pulled past each end, in points (zero when it is not); pure, so the formula is tested without a finger.
struct ListPull: Equatable {
    var top: CGFloat
    var bottom: CGFloat

    /// Creates a pull from its two distances.
    init(top: CGFloat, bottom: CGFloat) {
        self.top = top
        self.bottom = bottom
    }

    /// The pull `geometry` shows: past the top above its inset, past the end of the content above the bottom inset (a list shorter
    /// than its viewport is pulled from where its content ends).
    init(_ geometry: ScrollGeometry) {
        top = max(-(geometry.contentOffset.y + geometry.contentInsets.top), 0)
        bottom = max(
            ReaderScrollGeometry.pastEnd(
                offsetY: geometry.contentOffset.y, viewportHeight: geometry.containerSize.height,
                contentHeight: geometry.contentSize.height, insetTop: geometry.contentInsets.top,
                insetBottom: geometry.contentInsets.bottom
            ), 0
        )
    }
}

/// Pull to refresh from the top and from the bottom of a scrolling list (#1207), replacing the system's `.refreshable`, which exists
/// at the top only: an icon grows with the pull (`PullRefreshRule`), one haptic and the refresh come when it is full, and a release
/// before that does nothing. Built on the scroll geometry and phase, with the system symbol and no custom physics (the operator's
/// rule of #1070). VoiceOver keeps a refresh through an "Actualiser" action on the list.
private struct PullToRefresh: ViewModifier {
    let isRefreshing: Bool
    let refresh: @MainActor () async -> Void

    @State private var tracker = PullEdgesTracker()
    @State private var lastPull = ListPull(top: 0, bottom: 0)
    @State private var isInteracting = false
    @State private var topScale: CGFloat = 0
    @State private var bottomScale: CGFloat = 0
    /// The end whose pull started the refresh that is running: only that icon turns, a load of another cause turns none.
    @State private var pulledEdge: PullEdge?

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, phase in
                isInteracting = phase == .interacting
                moved(lastPull)
            }
            .onScrollGeometryChange(for: ListPull.self) { ListPull($0) } action: { _, pull in
                moved(pull)
            }
            .overlay(alignment: .top) {
                PullRefreshIcon(progress: topScale, isRefreshing: pulledEdge == .top).allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                PullRefreshIcon(progress: bottomScale, isRefreshing: pulledEdge == .bottom).allowsHitTesting(false)
            }
            .accessibilityAction(named: "Actualiser") { Task { await refresh() } }
    }

    private func moved(_ pull: ListPull) {
        lastPull = pull
        let step = tracker.update(topPull: pull.top, bottomPull: pull.bottom, fingerDown: isInteracting)
        topScale = step.top
        bottomScale = step.bottom
        guard let edge = step.firedEdge, !isRefreshing else { return }
        HapticFeedback.live.impact(.light)
        pulledEdge = edge
        Task {
            await refresh()
            pulledEdge = nil
        }
    }
}

extension View {
    /// Pull to refresh from the top and the bottom of this list; `isRefreshing` keeps the icon turning until `refresh` is done.
    func pullToRefresh(isRefreshing: Bool, refresh: @escaping @MainActor () async -> Void) -> some View {
        modifier(PullToRefresh(isRefreshing: isRefreshing, refresh: refresh))
    }
}
