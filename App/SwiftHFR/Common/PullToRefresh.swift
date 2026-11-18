import SwiftUI

/// Pull to refresh from the top and from the bottom of a scrolling list (#1207), replacing the system's `.refreshable`, which exists
/// at the top only: an icon grows with the pull (`PullRefreshRule`), one haptic and the refresh come when it is full, and a release
/// before that does nothing. Built on the scroll geometry and phase, with the system symbol and no custom physics (the operator's
/// rule of #1070). VoiceOver keeps a refresh through an "Actualiser" action on the list.
private struct PullToRefresh: ViewModifier {
    let isRefreshing: Bool
    let refresh: @MainActor () async -> Void

    /// How far the list is pulled past each end, in points.
    private struct Pull: Equatable {
        var top: CGFloat
        var bottom: CGFloat
    }

    @State private var tracker = PullEdgesTracker()
    @State private var lastPull = Pull(top: 0, bottom: 0)
    @State private var isInteracting = false
    @State private var topScale: CGFloat = 0
    @State private var bottomScale: CGFloat = 0
    @State private var refreshesAtTop = true

    func body(content: Content) -> some View {
        content
            .onScrollPhaseChange { _, phase in
                isInteracting = phase == .interacting
                moved(lastPull)
            }
            .onScrollGeometryChange(for: Pull.self) { geometry in
                Pull(
                    top: max(-(geometry.contentOffset.y + geometry.contentInsets.top), 0),
                    bottom: max(
                        ReaderScrollGeometry.pastEnd(
                            offsetY: geometry.contentOffset.y, viewportHeight: geometry.containerSize.height,
                            contentHeight: geometry.contentSize.height, insetTop: geometry.contentInsets.top,
                            insetBottom: geometry.contentInsets.bottom
                        ), 0
                    )
                )
            } action: { _, pull in
                moved(pull)
            }
            .overlay(alignment: .top) {
                PullRefreshIcon(progress: topScale, isRefreshing: isRefreshing && refreshesAtTop).allowsHitTesting(false)
            }
            .overlay(alignment: .bottom) {
                PullRefreshIcon(progress: bottomScale, isRefreshing: isRefreshing && !refreshesAtTop).allowsHitTesting(false)
            }
            .accessibilityAction(named: "Actualiser") { Task { await refresh() } }
    }

    private func moved(_ pull: Pull) {
        lastPull = pull
        let step = tracker.update(topPull: pull.top, bottomPull: pull.bottom, fingerDown: isInteracting)
        topScale = step.top
        bottomScale = step.bottom
        guard step.fires, !isRefreshing else { return }
        refreshesAtTop = step.firesAtTop
        HapticFeedback.live.impact(.light)
        Task { await refresh() }
    }
}

extension View {
    /// Pull to refresh from the top and the bottom of this list; `isRefreshing` keeps the icon turning until `refresh` is done.
    func pullToRefresh(isRefreshing: Bool, refresh: @escaping @MainActor () async -> Void) -> some View {
        modifier(PullToRefresh(isRefreshing: isRefreshing, refresh: refresh))
    }
}
