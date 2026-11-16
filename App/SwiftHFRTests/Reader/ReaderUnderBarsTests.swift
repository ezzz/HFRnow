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
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        for _ in 0..<50 where (seen.insets?.bottom ?? 0) < 80 { try await Task.sleep(for: .milliseconds(20)) }
        let insets = try #require(seen.insets)
        #expect(insets.top >= 100, "top: \(insets.top)")
        #expect(insets.bottom >= 80, "bottom: \(insets.bottom)")
    }

    /// Issue #641, as the reader is built: inside a navigation stack with its inline title bar and its bottom bar, the page is
    /// handed the bars' real heights, so the first post's header opens below the top bar and the last lines above the bottom
    /// one (`ReaderInsetsWebTests` pins the page to that edge). Before #878 the reader read its insets under
    /// `ignoresSafeArea` and got zero here.
    @Test func inANavigationStackTheTopBarAndTheBottomBarReachThePage() async throws {
        let seen = Seen()
        let host = UIHostingController(rootView: NavigationStack {
            ReaderUnderBars { insets in
                seen.insets = insets
                return Color.clear
            }
            .navigationTitle("Sujet")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .bottomBar) { Button("Page suivante", systemImage: "chevron.forward") {} }
            }
        })
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 390, height: 844)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        let statusBar = window.safeAreaInsets.top
        for _ in 0..<100 where (seen.insets?.top ?? 0) < statusBar + 44 || (seen.insets?.bottom ?? 0) < 44 {
            try await Task.sleep(for: .milliseconds(20))
        }
        let insets = try #require(seen.insets)
        // At least a bar each (44 points), on top of what the window's own safe area adds (status bar, Dynamic Island).
        #expect(insets.top >= window.safeAreaInsets.top + 44, "top: \(insets.top), window: \(window.safeAreaInsets)")
        #expect(insets.bottom >= 44, "bottom: \(insets.bottom)")
    }
}
