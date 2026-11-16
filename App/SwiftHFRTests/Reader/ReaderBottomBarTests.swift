@testable import SwiftHFR
import SwiftUI
import Testing

/// Issue #649: the reader's bottom controls beside a visible tab bar. Topic and private conversation share this bar.
@MainActor
struct ReaderBottomBarTests {
    /// Issue #649: a Pro Max in landscape is regular width with the tab bar shown: the system bottom bar would sit under it.
    @Test func besideAVisibleTabBarTheControlsAreAStripAboveIt() {
        func placement(root tabBar: Bool, _ sizeClass: UserInterfaceSizeClass, selected: Bool = true) -> ReaderBottomBar.Placement {
            ReaderBottomBar.placement(
                rootHasTabBar: tabBar, tabBar: ReaderTabBar.visibility(sizeClass: sizeClass, isSelectedTab: selected)
            )
        }
        #expect(placement(root: true, .regular) == .inset)
        // Compact width hides the tab bar while the reader is open: the system bottom bar is free.
        #expect(placement(root: true, .compact) == .bottomBar)
        // The iPad sidebar root has no tab bar.
        #expect(placement(root: false, .regular) == .bottomBar)
        #expect(placement(root: false, .compact) == .bottomBar)
    }
}
