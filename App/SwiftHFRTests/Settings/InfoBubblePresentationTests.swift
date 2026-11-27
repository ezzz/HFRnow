@testable import SwiftHFR
import SwiftUI
import Testing

/// #1181 (HIG › Popovers: reserve popovers for wide views, use a sheet in compact ones).
struct InfoBubblePresentationTests {
    /// The only part of the form that is a plain value; that the sheet really scrolls at AX sizes, and that the popover stays a
    /// popover on iPad and on a Plus/Pro Max in landscape, is the Mac check on #893.
    @Test func theSheetOpensAtHalfHeightAndGrowsForALongText() {
        #expect(InfoBubblePresentation.sheetDetents == [.medium, .large])
    }
}
