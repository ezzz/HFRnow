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
        window.frame = scene.effectiveGeometry.coordinateSpace.bounds
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        let statusBar = window.safeAreaInsets.top
        for _ in 0..<100 where (seen.insets?.top ?? 0) < statusBar + 44 || Self.barButton(in: window, below: statusBar) == nil {
            try await Task.sleep(for: .milliseconds(20))
        }
        // Let the bar's own contribution reach the page before reading it.
        try await Task.sleep(for: .milliseconds(200))
        let insets = try #require(seen.insets)
        // At least a bar each (44 points), on top of what the window's own safe area adds (status bar, Dynamic Island).
        #expect(insets.top >= window.safeAreaInsets.top + 44, "top: \(insets.top), window: \(window.safeAreaInsets)")
        // The bottom bar itself must exist: its button is a real view below the top bar.
        let button = try #require(Self.barButton(in: window, below: statusBar), "no bottom bar button in the window")
        let reserved = window.safeAreaInsets
        let screen = window.bounds
        if max(reserved.left, reserved.right) >= 44 {
            // The window already reserves a side for the system bars (the iPhone Duo cover screen moves the bottom bar there): the
            // inset alone cannot show the bar, so the bar's button must sit inside that side band and the page gets the band.
            let onTheRight = reserved.right >= reserved.left
            let band = onTheRight ? reserved.right : reserved.left
            #expect((onTheRight ? insets.trailing : insets.leading) >= band, "page \(insets), window: \(reserved)")
            let frame = button.convert(button.bounds, to: nil)
            let inBand = onTheRight ? frame.minX >= screen.width - band : frame.maxX <= band
            #expect(inBand, "button \(frame) outside the \(band) pt side band")
        } else {
            #expect(insets.bottom >= 44, "bottom: \(insets.bottom), window: \(reserved)")
            let frame = button.convert(button.bounds, to: nil)
            #expect(frame.maxY > screen.height - insets.bottom, "button \(frame), page \(insets)")
        }
        let safe = host.view.safeAreaInsets
        #expect(insets.bottom >= safe.bottom && insets.leading >= safe.left && insets.trailing >= safe.right, "\(insets), host: \(safe)")
    }

    /// The system's button of a bottom-bar item (`_UIButtonBarButton`), below the top bar.
    private static func barButton(in view: UIView, below top: CGFloat) -> UIView? {
        if String(describing: type(of: view)).contains("ButtonBarButton"), view.convert(view.bounds, to: nil).minY > top + 44 {
            return view
        }
        for sub in view.subviews { if let found = barButton(in: sub, below: top) { return found } }
        return nil
    }
}
