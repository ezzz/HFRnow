import Testing
@testable import HFRStorage

@Suite struct ThemeColorTests {
    @Test func parsesTheLegacySerialization() {
        let color = ThemeColor(serialized: "{0.250, 0.500, 0.750, 1.000}")
        #expect(color == ThemeColor(red: 0.25, green: 0.5, blue: 0.75, alpha: 1))
    }

    @Test func serializesWithThreeDecimalsAndAPoint() {
        #expect(ThemeColor(red: 0.12345, green: 1, blue: 0, alpha: 0.5).serialized == "{0.123, 1.000, 0.000, 0.500}")
        #expect(ThemeColor(red: 1234.5, green: 0, blue: 0, alpha: 1).serialized == "{1234.500, 0.000, 0.000, 1.000}")
    }

    @Test(arguments: ["", "0.1, 0.2, 0.3, 1", "{0.1, 0.2, 0.3}", "{0.1, 0.2, 0.3, 0.4, 0.5}", "{a, b, c, d}", "{0.1,, 0.3, 1}",
                      "{nan, 0, 0, 1}", "{inf, 0, 0, 1}"])
    func rejectsMalformedStrings(text: String) {
        #expect(ThemeColor(serialized: text) == nil)
    }

    @Test func toleratesSpacingVariants() {
        #expect(ThemeColor(serialized: " {0.1,0.2 ,0.3, 1} ") == ThemeColor(red: 0.1, green: 0.2, blue: 0.3, alpha: 1))
    }

    @Test func roundTripsAtThreeDecimals() {
        let color = ThemeColor(red: 0.5, green: 0.25, blue: 0.125, alpha: 0.75)
        #expect(ThemeColor(serialized: color.serialized) == color)
    }
}
