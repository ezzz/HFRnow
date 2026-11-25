@testable import SwiftHFR
import SwiftUI
import Testing

/// #1181 (HIG › Popovers: reserve popovers for wide views, use a sheet in compact ones).
struct InfoBubblePresentationTests {
    @Test func compactWidthGetsASheetAndWideWidthKeepsThePopover() {
        #expect(InfoBubblePresentation.isSheet(.compact))
        #expect(!InfoBubblePresentation.isSheet(.regular))
        #expect(!InfoBubblePresentation.isSheet(nil))
    }

    @Test func theSheetGrowsToFullHeightForALongText() {
        #expect(InfoBubblePresentation.sheetDetents == [.medium, .large])
    }
}
