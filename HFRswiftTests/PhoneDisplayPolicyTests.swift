import XCTest
@testable import HFRswift

/// iPhone Duo display classification and the inline-title rule behind the cover screen freeze fix.
final class PhoneDisplayPolicyTests: XCTestCase {
    func testCoverScreenRecognisedBySideStripInPortrait() {
        let kind = PhoneDisplayPolicy.displayKind(
            isPhone: true, usesSidebarRoot: false, isPortrait: true,
            horizontalSafeAreaInset: 44, hasShownExpandedLayout: false
        )
        XCTAssertEqual(kind, .duoCover)
    }

    func testCoverScreenRecognisedOnceDeviceWasUnfolded() {
        let kind = PhoneDisplayPolicy.displayKind(
            isPhone: true, usesSidebarRoot: false, isPortrait: true,
            horizontalSafeAreaInset: 0, hasShownExpandedLayout: true
        )
        XCTAssertEqual(kind, .duoCover)
    }

    func testRegularIPhoneInPortraitIsNotCover() {
        let kind = PhoneDisplayPolicy.displayKind(
            isPhone: true, usesSidebarRoot: false, isPortrait: true,
            horizontalSafeAreaInset: 0, hasShownExpandedLayout: false
        )
        XCTAssertEqual(kind, .other)
    }

    func testRegularIPhoneInLandscapeIsNotCover() {
        // Landscape iPhones have side insets for the sensor housing: not a cover screen.
        let kind = PhoneDisplayPolicy.displayKind(
            isPhone: true, usesSidebarRoot: false, isPortrait: false,
            horizontalSafeAreaInset: 59, hasShownExpandedLayout: false
        )
        XCTAssertEqual(kind, .other)
    }

    func testSplitRootOnPhoneIsInnerDisplay() {
        let kind = PhoneDisplayPolicy.displayKind(
            isPhone: true, usesSidebarRoot: true, isPortrait: true,
            horizontalSafeAreaInset: 0, hasShownExpandedLayout: true
        )
        XCTAssertEqual(kind, .duoInner)
    }

    func testIPadIsNeverADuoDisplay() {
        let kind = PhoneDisplayPolicy.displayKind(
            isPhone: false, usesSidebarRoot: true, isPortrait: true,
            horizontalSafeAreaInset: 20, hasShownExpandedLayout: true
        )
        XCTAssertEqual(kind, .other)
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

    private func inline(_ kind: PhoneDisplayKind, isPhone: Bool, regularBoth: Bool) -> Bool {
        PhoneDisplayPolicy.usesInlineRootTitle(kind: kind, isPhone: isPhone, isRegularInBothDimensions: regularBoth)
    }
}
