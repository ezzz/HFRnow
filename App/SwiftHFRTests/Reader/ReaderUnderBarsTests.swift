@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// Issues #852 and #641: the page runs under the bars, and what they cover must reach the web view. The insets are what a
/// hosting controller's safe area says (a navigation bar on top, the floating page controls below).
@MainActor
@Suite(.serialized)
struct ReaderUnderBarsTests {
    private final class Seen {
        var insets: EdgeInsets?
    }

    @Test func theBarsOfTheSafeAreaReachTheContentAtBothEdges() async throws {
        let seen = Seen()
        let host = UIHostingController(rootView: ReaderUnderBars { insets in
            seen.insets = insets
            return Color.clear
        })
        host.additionalSafeAreaInsets = UIEdgeInsets(top: 100, left: 0, bottom: 80, right: 0)
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 800)
        window.rootViewController = host
        window.isHidden = false
        host.view.layoutIfNeeded()
        for _ in 0..<50 where (seen.insets?.bottom ?? 0) < 80 { try await Task.sleep(for: .milliseconds(20)) }
        let insets = try #require(seen.insets)
        #expect(insets.top >= 100, "top: \(insets.top)")
        #expect(insets.bottom >= 80, "bottom: \(insets.bottom)")
    }
}
