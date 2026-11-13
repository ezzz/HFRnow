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

    @Test("an iPhone at regular width (landscape Pro Max) has the tab bar, so its pager is an inset")
    func phoneAtRegularWidthUsesInset() {
        #expect(RootNavigationView.rootHasTabBar(idiom: .phone, sizeClass: .regular))
    }

    @Test("an iPad at regular width has the sidebar root, no tab bar")
    func padAtRegularWidthHasNoTabBar() {
        #expect(!RootNavigationView.rootHasTabBar(idiom: .pad, sizeClass: .regular))
    }

    @Test("a compact-width iPad (Slide Over) has the tab bar")
    func compactPadHasTabBar() {
        #expect(RootNavigationView.rootHasTabBar(idiom: .pad, sizeClass: .compact))
    }

    @Test("an iPhone at compact width has the tab bar")
    func compactPhoneHasTabBar() {
        #expect(RootNavigationView.rootHasTabBar(idiom: .phone, sizeClass: .compact))
    }

    @Test("an unknown size class has the tab bar")
    func unknownSizeClassHasTabBar() {
        #expect(RootNavigationView.rootHasTabBar(idiom: .pad, sizeClass: nil))
    }

    @Test("a screen outside the roots assumes the tab bar")
    func defaultAssumesTabBar() {
        #expect(EnvironmentValues().rootHasTabBar)
    }
}
