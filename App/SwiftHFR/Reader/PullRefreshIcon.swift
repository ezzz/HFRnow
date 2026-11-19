import SwiftUI

/// The refresh icon of a pull from either end of a page (#1207): it grows with the pull (`PullRefreshRule.scale`), turns while the
/// refresh runs, and is gone at rest. With Reduce Motion it appears at once at full size, with no growth.
struct PullRefreshIcon: View {
    /// The pull as a scale from 0 to 1.
    let progress: CGFloat
    /// A refresh is running: the icon stays, turning, until it is done.
    var isRefreshing = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        let isShown = progress > 0 || isRefreshing
        Image(systemName: "arrow.clockwise")
            .font(.title3.weight(.semibold))
            .padding(10)
            .background(.regularMaterial, in: Circle())
            .scaleEffect(reduceMotion || isRefreshing ? 1 : max(progress, 0.01))
            .opacity(isShown ? 1 : 0)
            .symbolEffect(.rotate, options: .repeating, isActive: isRefreshing)
            // The refresh stays reachable for VoiceOver through the screen's own "Actualiser" actions.
            .accessibilityHidden(true)
    }
}
