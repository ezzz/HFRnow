@testable import SwiftHFR
import SwiftUI
import Testing
import UIKit

/// Issue #431 (UXD-24): on a large iPhone in landscape (regular width, compact height) the tab root's splits collapse to a
/// stack, so the reader is pushed over the list at full width, as legacy's tab root; an iPad and an iPhone regular in both
/// dimensions keep their width.
@MainActor
@Suite(.serialized)
struct TabSplitWidthTests {
    @Test func aPhoneInLandscapeGivesItsSplitsACompactWidth() {
        #expect(RootNavigationView.tabSplitSizeClass(idiom: .phone, horizontal: .regular, vertical: .compact) == .compact)
        #expect(RootNavigationView.tabSplitSizeClass(idiom: .phone, horizontal: .compact, vertical: .compact) == .compact)
        #expect(RootNavigationView.tabSplitSizeClass(idiom: .phone, horizontal: .compact, vertical: .regular) == .compact)
    }

    @Test func anIPadAndAPhoneRegularInBothDimensionsKeepTheirWidth() {
        #expect(RootNavigationView.tabSplitSizeClass(idiom: .pad, horizontal: .regular, vertical: .compact) == .regular)
        #expect(RootNavigationView.tabSplitSizeClass(idiom: .pad, horizontal: .regular, vertical: .regular) == .regular)
        #expect(RootNavigationView.tabSplitSizeClass(idiom: .pad, horizontal: .compact, vertical: .regular) == .compact)
        #expect(RootNavigationView.tabSplitSizeClass(idiom: .phone, horizontal: .regular, vertical: .regular) == .regular)
    }

    private final class Seen {
        var listWidth: UserInterfaceSizeClass?
        var detailShown = false
    }

    private struct Probe: View {
        let seen: Seen
        let idiom: UIUserInterfaceIdiom

        var body: some View {
            NavigationSplitView {
                ListSide(seen: seen)
            } detail: {
                Text("Sujet").onAppear { seen.detailShown = true }
            }
            .modifier(TabSplitWidth(idiom: idiom))
        }
    }

    private struct ListSide: View {
        let seen: Seen
        @Environment(\.horizontalSizeClass) private var width

        var body: some View {
            Text("Liste").onAppear { seen.listWidth = width }
        }
    }

    private func splitViews(in controller: UIViewController) -> [UISplitViewController] {
        let own = (controller as? UISplitViewController).map { [$0] } ?? []
        return own + controller.children.flatMap { splitViews(in: $0) }
    }

    /// A Pro Max in landscape, as the window's traits say it (932 × 430, regular width, compact height). On a phone the split
    /// collapses: the list sees a compact width and the detail is not shown beside it. The same window with the iPad rule shows
    /// both columns, so the window really is regular width.
    @Test(arguments: [UIUserInterfaceIdiom.phone, .pad])
    func theTabSplitCollapsesOnALandscapePhoneOnly(idiom: UIUserInterfaceIdiom) async throws {
        let seen = Seen()
        let host = UIHostingController(rootView: Probe(seen: seen, idiom: idiom))
        host.traitOverrides.horizontalSizeClass = .regular
        host.traitOverrides.verticalSizeClass = .compact
        let scene = try #require(UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene)
        let window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 932, height: 430)
        window.rootViewController = host
        window.isHidden = false
        defer { window.isHidden = true }
        host.view.layoutIfNeeded()
        for _ in 0..<100 where seen.listWidth == nil || (idiom == .pad && !seen.detailShown) {
            try await Task.sleep(for: .milliseconds(20))
            window.layoutIfNeeded()
        }
        // Long enough for a detail column to appear beside the list, had the split not collapsed.
        try await Task.sleep(for: .milliseconds(500))
        let splits = splitViews(in: host)
        #expect(!splits.isEmpty)
        if idiom == .phone {
            #expect(seen.listWidth == .compact)
            #expect(!seen.detailShown, "the reader's column is shown beside the list")
            #expect(splits.allSatisfy { $0.isCollapsed }, "collapsed: \(splits.map { $0.isCollapsed })")
        } else {
            #expect(seen.listWidth == .regular)
            #expect(seen.detailShown, "the detail column is not shown: the window is not regular width")
            #expect(splits.allSatisfy { !$0.isCollapsed }, "collapsed: \(splits.map { $0.isCollapsed })")
        }
    }
}
