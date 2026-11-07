@testable import SwiftHFR
import SwiftUI
import Testing

struct RowTintTests {
    @Test("Tint strength: 0.10 light, 0.16 dark")
    func strengthByScheme() {
        #expect(RowTint.strength(scheme: .light, contrast: .standard) == 0.10)
        #expect(RowTint.strength(scheme: .dark, contrast: .standard) == 0.16)
    }

    @Test("Increase Contrast adds 0.08 in both schemes")
    func strengthIncreasedContrast() {
        #expect(abs(RowTint.strength(scheme: .light, contrast: .increased) - 0.18) < 1e-9)
        #expect(abs(RowTint.strength(scheme: .dark, contrast: .increased) - 0.24) < 1e-9)
    }

    @Test("An unread row is tinted, a read one is not")
    func unreadTint() {
        #expect(MessageRowView.rowTint(isUnread: true, isSelected: false) != nil)
        #expect(MessageRowView.rowTint(isUnread: false, isSelected: false) == nil)
    }

    @Test("The selected row keeps the system selection highlight")
    func selectedRowIsNotTinted() {
        #expect(MessageRowView.rowTint(isUnread: true, isSelected: true) == nil)
    }
}
