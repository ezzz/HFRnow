import Testing
@testable import HFRStorage

@Suite struct PseudoNormalizerTests {
    @Test(arguments: [
        ("Marc", "marc"), ("MARC", "marc"), ("Ma\u{200B}rc", "marc"), ("\u{200B}Marc\u{200B}", "marc"),
        ("Éric", "éric"), ("a b", "a b"), ("", ""), ("\u{200B}\u{200B}", "")
    ])
    func normalizesZeroWidthSpacesAndCase(input: String, expected: String) {
        #expect(PseudoNormalizer.normalize(input) == expected)
    }

    @Test func matchesIgnoresCaseAndInvisibleCharactersInBothOrders() {
        #expect(PseudoNormalizer.matches("Ma\u{200B}rc", "mARC"))
        #expect(PseudoNormalizer.matches("mARC", "Ma\u{200B}rc"))
        #expect(!PseudoNormalizer.matches("Marc", "Marc2"))
    }

    @Test func doesNotTrimOrFoldOtherWhitespace() {
        #expect(!PseudoNormalizer.matches("Marc ", "Marc"))
    }
}
