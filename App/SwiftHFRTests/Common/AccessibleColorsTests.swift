@testable import SwiftHFR
import Testing

struct AccessibleColorsTests {
    private typealias Colors = AccessibleColors
    private typealias RGB = AccessibleColors.RGB

    @Test func contrastMatchesWCAGReferenceValues() {
        #expect(Colors.contrast(.white, .black) == 21)
        #expect(Colors.contrast(.white, .white) == 1)
        // Rounded reference: #767676 on white is the classic 4.54:1.
        #expect(abs(Colors.contrast(RGB(red: 118, green: 118, blue: 118), .white) - 4.54) < 0.01)
    }

    @Test(arguments: [false, true])
    func badgeTextReadsOnItsFill(dark: Bool) {
        let ratio = Colors.contrast(Colors.rgb(.badgeText, dark: dark), Colors.rgb(.badgeFill, dark: dark))
        #expect(ratio >= 4.5)
    }

    /// The outlined badge draws the fill colour on the row's background: white or black, and the grouped card greys.
    @Test(arguments: [
        (false, RGB(red: 255, green: 255, blue: 255)), (false, RGB(red: 242, green: 242, blue: 247)),
        (true, RGB(red: 0, green: 0, blue: 0)), (true, RGB(red: 28, green: 28, blue: 30)),
    ])
    func outlinedBadgeReadsOnTheCard(dark: Bool, card: RGB) {
        #expect(Colors.contrast(Colors.rgb(.badgeFill, dark: dark), card) >= 4.5)
    }

    @Test(arguments: [
        (false, RGB(red: 255, green: 255, blue: 255)), (false, RGB(red: 242, green: 242, blue: 247)),
        (true, RGB(red: 0, green: 0, blue: 0)), (true, RGB(red: 28, green: 28, blue: 30)),
    ])
    func messageColoursReadOnTheCard(dark: Bool, card: RGB) {
        for role in [Colors.Role.errorText, .warningText] {
            #expect(Colors.contrast(Colors.rgb(role, dark: dark), card) >= 4.5)
        }
    }

    /// The accent capsule of #646: white on the light cyan, 1.5:1. It is what the fixed fill replaces.
    @Test func theOldAccentCapsuleFailed() {
        #expect(Colors.contrast(.white, RGB(red: 89, green: 227, blue: 255)) < 2)
    }
}
