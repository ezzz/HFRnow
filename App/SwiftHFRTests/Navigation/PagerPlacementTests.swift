import SwiftUI
import Testing

@testable import SwiftHFR

/// #565: the system bottom bar of a list sat inside the iPhone floating tab bar's frame. The placement follows the root that was
/// built (tab bar or sidebar), never the size class: a Plus / Pro Max iPhone in landscape is regular width with the tab bar.
@Suite("Pager placement")
struct PagerPlacementTests {
    @Test("the tab bar root gets the pager as an inset above it")
    func tabBarRootUsesInset() {
        #expect(PagerPlacement(rootHasTabBar: true) == .inset)
    }

    @Test("the sidebar root (no tab bar) keeps the system bottom bar")
    func sidebarRootUsesBottomBar() {
        #expect(PagerPlacement(rootHasTabBar: false) == .bottomBar)
    }

    @Test("an iPhone at regular width (landscape Pro Max) builds the tab root, so its pager is an inset")
    func phoneAtRegularWidthUsesInset() {
        let sidebar = RootNavigationView.usesSidebarRoot(idiom: .phone, sizeClass: .regular)
        #expect(PagerPlacement(rootHasTabBar: !sidebar) == .inset)
    }

    @Test("an iPad at regular width builds the sidebar root, so its pager is the bottom bar")
    func padAtRegularWidthUsesBottomBar() {
        let sidebar = RootNavigationView.usesSidebarRoot(idiom: .pad, sizeClass: .regular)
        #expect(PagerPlacement(rootHasTabBar: !sidebar) == .bottomBar)
    }

    @Test("a compact-width iPad (Slide Over) builds the tab root")
    func compactPadUsesInset() {
        let sidebar = RootNavigationView.usesSidebarRoot(idiom: .pad, sizeClass: .compact)
        #expect(PagerPlacement(rootHasTabBar: !sidebar) == .inset)
    }

    @Test("a screen outside the roots assumes the tab bar")
    func defaultAssumesTabBar() {
        #expect(EnvironmentValues().rootHasTabBar)
    }
}
