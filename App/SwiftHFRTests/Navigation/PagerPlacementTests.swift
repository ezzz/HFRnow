import SwiftUI
import Testing

@testable import SwiftHFR

/// #565: on iPhone the system bottom bar of a list sat inside the floating tab bar's frame; compact width (the tab bar root) now
/// gets the pager as an inset above the tab bar, regular width keeps the system bottom bar.
@Suite("Pager placement")
struct PagerPlacementTests {
    @Test("compact width has a tab bar: the pager is an inset above it")
    func compactUsesInset() {
        #expect(PagerPlacement(horizontalSizeClass: .compact) == .inset)
    }

    @Test("regular width (sidebar root, no tab bar) keeps the system bottom bar")
    func regularUsesBottomBar() {
        #expect(PagerPlacement(horizontalSizeClass: .regular) == .bottomBar)
    }

    @Test("an unknown size class behaves like compact: a hidden pager is worse than a duplicated one")
    func unknownUsesInset() {
        #expect(PagerPlacement(horizontalSizeClass: nil) == .inset)
    }
}
