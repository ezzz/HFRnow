import Testing
@testable import HFRParsing

@Suite("Text helpers")
struct HFRTextTests {
    @Test(
        "First integer: MP badge variants",
        arguments: [
            ("Vous avez 3 nouveaux messages", 3),        // home page `.cCatTopic`
            ("Vous avez 12 nouveaux messages privés", 12),
            ("3 nouveaux messages", 3),                  // leading digits (legacy regex needed text before)
            ("Vous avez 7", 7),                          // trailing digits (legacy regex gave 0)
            ("(5)", 5),
            ("\n\t 42 \n", 42),
            ("1.5 messages", 1),
            ("007", 7)
        ]
    )
    func firstInteger(text: String, expected: Int) {
        #expect(HFRText.firstInteger(in: text) == expected)
    }

    @Test(
        "First integer: none or overflow",
        arguments: ["", "Aucun nouveau message", "٣ messages", "99999999999999999999999"]
    )
    func noInteger(text: String) {
        #expect(HFRText.firstInteger(in: text) == nil)
    }

    @Test(
        "Pseudo normalization removes U+200B and trims",
        arguments: [
            ("Pseudo\u{200B}Exemple", "PseudoExemple"),
            ("\u{200B}Pseudo Exemple\u{200B}", "Pseudo Exemple"),
            ("  Pseudo\u{200B}\u{200B}Long  \n", "PseudoLong"),
            ("Pseudo", "Pseudo"),
            ("\u{200B}", "")
        ]
    )
    func normalizedPseudo(raw: String, expected: String) {
        #expect(HFRText.normalizedPseudo(raw) == expected)
    }

    @Test("Comparison key ignores case and zero-width spaces")
    func comparisonKey() {
        #expect(HFRText.pseudoComparisonKey("Pseudo\u{200B}Exemple") == HFRText.pseudoComparisonKey("pseudoexemple"))
        #expect(HFRText.pseudoComparisonKey("PseudoA") != HFRText.pseudoComparisonKey("PseudoB"))
    }
}
