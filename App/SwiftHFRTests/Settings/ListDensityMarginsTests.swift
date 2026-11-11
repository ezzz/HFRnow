@testable import SwiftHFR
import Testing

/// The side margins of the inset-grouped lists follow the density (#799).
struct ListDensityMarginsTests {
    @Test("Regular keeps the system outer margin and the legacy 16 pt inner one")
    func regularMargins() {
        #expect(ListDensity.regular.outerMargin == nil)
        #expect(ListDensity.regular.rowInsets.leading == 16)
        #expect(ListDensity.regular.rowInsets.trailing == 16)
    }

    @Test("Compact sets a 10 pt outer margin and a 7 pt inner one")
    func compactMargins() {
        #expect(ListDensity.compact.outerMargin == 10)
        #expect(ListDensity.compact.rowInsets.leading == 7)
        #expect(ListDensity.compact.rowInsets.trailing == 7)
    }

    @Test("Compact margins are narrower than regular on both sides")
    func compactIsNarrower() {
        #expect(ListDensity.compact.rowInsets.leading < ListDensity.regular.rowInsets.leading)
        #expect((ListDensity.compact.outerMargin ?? 0) > 0)
    }
}
