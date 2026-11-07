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

    @Test("The weight scales the strength; the default is 1")
    func weightScales() {
        #expect(RowTint.strength(scheme: .light, contrast: .standard, weight: 0.5) == 0.05)
        #expect(RowTint.strength(scheme: .dark, contrast: .standard, weight: 1) == RowTint.strength(scheme: .dark, contrast: .standard))
        #expect(RowTint().weight == 1)
    }
}
