import SwiftUI

/// Counts a hosted view's rendered updates (#1194): a negative checked after `settled()` covers at least the update it asked
/// for, instead of a delay a slow runner may not honour. Put a `RenderProbeView` of it in the host.
@MainActor
@Observable
final class RenderProbe {
    private(set) var asked = 0
    @ObservationIgnored fileprivate(set) var rendered = 0

    /// Asks for an update and returns whether the host rendered it (within about two seconds).
    func settled() async -> Bool {
        asked += 1
        for _ in 0..<100 where rendered != asked { try? await Task.sleep(for: .milliseconds(20)) }
        return rendered == asked
    }
}

/// The view that reports a probe's updates once SwiftUI has applied them.
struct RenderProbeView: View {
    let probe: RenderProbe

    var body: some View {
        Color.clear.onChange(of: probe.asked, initial: true) { _, asked in probe.rendered = asked }
    }
}
