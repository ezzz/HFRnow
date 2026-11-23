import XCTest
@testable import HFRswift

/// iPhone Duo display classification and the rules behind the cover screen fixes (freeze, thumb reach).
final class PhoneDisplayPolicyTests: XCTestCase {
    private let portrait = WindowShape(isPortrait: true, horizontalSafeAreaInset: 0)
    private let portraitWithSideStrip = WindowShape(isPortrait: true, horizontalSafeAreaInset: 44)
    private let landscapeWithSideInsets = WindowShape(isPortrait: false, horizontalSafeAreaInset: 59)

    func testCoverScreenRecognisedBySideStripInPortrait() {
        XCTAssertEqual(kind(window: portraitWithSideStrip), .duoCover)
    }

    func testCoverScreenRecognisedByModelEvenWithoutSideStripOrLandscape() {
        XCTAssertEqual(kind(foldable: true, window: portrait), .duoCover)
        XCTAssertEqual(kind(foldable: true, window: landscapeWithSideInsets), .duoCover)
    }

    func testCoverScreenRecognisedOnceUnfoldedThisLaunch() {
        XCTAssertEqual(kind(window: portrait, seenUnfolded: true), .duoCover)
    }

    func testRegularIPhoneInPortraitIsNotCover() {
        XCTAssertEqual(kind(window: portrait), .other)
    }

    func testRegularIPhoneInLandscapeIsNotCover() {
        // Landscape iPhones have side insets for the sensor housing: not a cover screen.
        XCTAssertEqual(kind(window: landscapeWithSideInsets), .other)
    }

    func testSplitRootOnPhoneIsInnerDisplay() {
        XCTAssertEqual(kind(sidebar: true, foldable: true, window: portrait), .duoInner)
    }

    func testIPadIsNeverADuoDisplay() {
        XCTAssertEqual(kind(isPhone: false, sidebar: true, foldable: true, window: portraitWithSideStrip), .other)
    }

    func testFoldableModelIdentifiers() {
        XCTAssertTrue(PhoneDisplayPolicy.isFoldableModel("iPhone19,4"))
        XCTAssertFalse(PhoneDisplayPolicy.isFoldableModel("iPhone18,1"))
        XCTAssertFalse(PhoneDisplayPolicy.isFoldableModel(""))
    }

    func testInlineTitleOnBothDuoDisplays() {
        XCTAssertTrue(inline(.duoCover, isPhone: true, regularBoth: false))
        XCTAssertTrue(inline(.duoInner, isPhone: true, regularBoth: true))
    }

    func testLargeTitleKeptOnRegularIPhoneAndIPad() {
        XCTAssertFalse(inline(.other, isPhone: true, regularBoth: false))
        XCTAssertFalse(inline(.other, isPhone: false, regularBoth: true))
    }

    func testInlineTitleFallbackOnRegularRegularPhoneOutsideRoot() {
        XCTAssertTrue(inline(.other, isPhone: true, regularBoth: true))
    }

    func testThumbActionsAtBottomOnCoverScreenOnly() {
        XCTAssertTrue(PhoneDisplayPolicy.placesThumbActionsAtBottom(kind: .duoCover))
        XCTAssertFalse(PhoneDisplayPolicy.placesThumbActionsAtBottom(kind: .duoInner))
        XCTAssertFalse(PhoneDisplayPolicy.placesThumbActionsAtBottom(kind: .other))
    }

    private func kind(
        isPhone: Bool = true, sidebar: Bool = false, foldable: Bool = false,
        window: WindowShape, seenUnfolded: Bool = false
    ) -> PhoneDisplayKind {
        PhoneDisplayPolicy.displayKind(
            isPhone: isPhone, usesSidebarRoot: sidebar, isFoldableModel: foldable,
            window: window, hasShownExpandedLayoutThisLaunch: seenUnfolded
        )
    }

    private func inline(_ kind: PhoneDisplayKind, isPhone: Bool, regularBoth: Bool) -> Bool {
        PhoneDisplayPolicy.usesInlineRootTitle(kind: kind, isPhone: isPhone, isRegularInBothDimensions: regularBoth)
    }
}
