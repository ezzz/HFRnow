@testable import SwiftHFR
import SwiftUI
import Testing

/// #1073 item 4: a selected row is a light accent tint in the classic look too, not the system's solid accent fill.
struct ListLookSelectionTests {
    @Test func classicSelectedRowDrawsTheLightTint() {
        #expect(ListLook.classic.rowBackground(isSelected: true) == Color.accentColor.opacity(0.15))
    }

    @Test func classicUnselectedRowKeepsTheCard() {
        #expect(ListLook.classic.rowBackground(isSelected: false) == nil)
    }

    @Test func denseRowsKeepTheirBehaviour() {
        #expect(ListLook.dense.rowBackground(isSelected: true) == DenseListLook.selectedRowBackground)
        #expect(ListLook.dense.rowBackground(isSelected: false) == DenseListLook.rowBackground)
    }
}
