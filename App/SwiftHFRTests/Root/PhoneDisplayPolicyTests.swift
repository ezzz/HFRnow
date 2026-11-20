@testable import SwiftHFR
import Testing

/// LOT-147 (GAP-713): which iPhone Duo display the scene is on, and the cover screen's thumb-reach rule, as legacy's
/// `PhoneDisplayPolicy` @ 87fe0d1c (`HFRswiftTests/PhoneDisplayPolicyTests.swift:1-79`).
struct PhoneDisplayPolicyTests {
    private let portrait = WindowShape(isPortrait: true, horizontalSafeAreaInset: 0)
    /// The cover screen: its system chrome is a vertical strip on the right edge (Mac check of `87fe0d1c` on #372, check 2a).
    private let portraitWithSideStrip = WindowShape(isPortrait: true, horizontalSafeAreaInset: 44)
    /// A regular iPhone in landscape has side insets for the sensor housing.
    private let landscapeWithSideInsets = WindowShape(isPortrait: false, horizontalSafeAreaInset: 59)

    @Test func theCoverScreenIsRecognisedByItsSideStripInPortrait() {
        #expect(kind(window: portraitWithSideStrip) == .duoCover)
    }

    @Test func theCoverScreenIsRecognisedByTheModelWithoutAStripAndInLandscape() {
        #expect(kind(foldable: true, window: portrait) == .duoCover)
        #expect(kind(foldable: true, window: landscapeWithSideInsets) == .duoCover)
    }

    @Test func theCoverScreenIsRecognisedOnceUnfoldedThisLaunch() {
        #expect(kind(window: portrait, seenUnfolded: true) == .duoCover)
    }

    @Test func aRegularIPhoneIsNotACoverScreen() {
        #expect(kind(window: portrait) == .other)
        #expect(kind(window: landscapeWithSideInsets) == .other)
        // A side inset counts in portrait only: no other iPhone has one there.
        #expect(kind(window: WindowShape(isPortrait: false, horizontalSafeAreaInset: 44)) == .other)
    }

    @Test func theSplitRootOnAPhoneIsTheInnerDisplay() {
        #expect(kind(sidebar: true, foldable: true, window: portrait) == .duoInner)
        #expect(kind(sidebar: true, window: portraitWithSideStrip) == .duoInner)
    }

    @Test func anIPadIsNeverADuoDisplay() {
        #expect(kind(isPhone: false, sidebar: true, foldable: true, window: portraitWithSideStrip, seenUnfolded: true) == .other)
        #expect(kind(isPhone: false, window: portraitWithSideStrip) == .other)
    }

    @Test func theFoldableModelIdentifiers() {
        #expect(PhoneDisplayPolicy.isFoldableModel("iPhone19,4"))
        #expect(!PhoneDisplayPolicy.isFoldableModel("iPhone18,1"))
        #expect(!PhoneDisplayPolicy.isFoldableModel(""))
        #expect(!PhoneDisplayPolicy.currentModelIdentifier.isEmpty)
    }

    /// « Retour » goes to the bottom of the toolbar column on the cover screen only (`PhoneDisplayPolicy.swift:59-64`).
    @Test func thumbActionsGoToTheBottomOnTheCoverScreenOnly() {
        #expect(PhoneDisplayPolicy.placesThumbActionsAtBottom(kind: .duoCover))
        #expect(!PhoneDisplayPolicy.placesThumbActionsAtBottom(kind: .duoInner))
        #expect(!PhoneDisplayPolicy.placesThumbActionsAtBottom(kind: .other))
        #expect(PhoneDisplayKind.duoCover.placesThumbActionsAtBottom)
        #expect(!PhoneDisplayKind.other.placesThumbActionsAtBottom)
    }

    private func kind(
        isPhone: Bool = true, sidebar: Bool = false, foldable: Bool = false, window: WindowShape, seenUnfolded: Bool = false
    ) -> PhoneDisplayKind {
        PhoneDisplayPolicy.displayKind(
            isPhone: isPhone, usesSidebarRoot: sidebar, isFoldableModel: foldable, window: window,
            hasShownExpandedLayoutThisLaunch: seenUnfolded
        )
    }
}
