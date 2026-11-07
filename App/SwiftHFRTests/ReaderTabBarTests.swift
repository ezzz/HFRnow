import SwiftUI
import Testing
@testable import SwiftHFR

/// GAP-008 / UXD-02: the reader hides the tab bar in compact width, only while its own tab is selected (#559).
struct ReaderTabBarTests {
    @Test func compactWidthInTheSelectedTabHides() {
        #expect(ReaderTabBar.visibility(sizeClass: .compact, isSelectedTab: true) == .hidden)
    }

    @Test func compactWidthInAnotherTabKeepsTheBar() {
        #expect(ReaderTabBar.visibility(sizeClass: .compact, isSelectedTab: false) == .automatic)
    }

    @Test func regularOrUnknownWidthKeepsTheBar() {
        #expect(ReaderTabBar.visibility(sizeClass: .regular, isSelectedTab: true) == .automatic)
        #expect(ReaderTabBar.visibility(sizeClass: nil, isSelectedTab: true) == .automatic)
    }
}
