@testable import SwiftHFR
import SwiftUI
import Testing

/// #1167 (HIG › Typography): the « Page numéro » sheet keeps legacy's 260 pt stop and can grow with Dynamic Type.
struct ReaderPageSheetDetentsTests {
    @Test func theSheetKeepsLegacysHeightAndCanGrow() {
        #expect(ReaderPagePicker.detents == [.height(260), .medium])
    }
}
