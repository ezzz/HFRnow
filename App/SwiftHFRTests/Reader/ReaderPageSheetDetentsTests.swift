@testable import SwiftHFR
import SwiftUI
import Testing

/// #1167 (HIG › Typography): the « Page numéro » sheet keeps legacy's 260 pt stop and can grow with Dynamic Type.
struct ReaderPageSheetDetentsTests {
    /// Only the plain value is testable here: that the sheet opens at 260 pt, scrolls and can be dragged taller at AX3/AX5 is the
    /// Mac check on #893.
    @Test func theSheetKeepsLegacysHeightAndCanGrow() {
        #expect(ReaderPagePicker.detents == [.height(260), .medium])
    }
}
