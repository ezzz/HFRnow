import Testing
@testable import HFRStorage

@Suite struct PseudoNormalizerTests {
    /// A pseudo, its cleaned form and its comparison form.
    struct Row: Sendable {
        let pseudo: String
        let cleaned: String
        let comparison: String

        init(_ pseudo: String, _ cleaned: String, _ comparison: String) {
            self.pseudo = pseudo
            self.cleaned = cleaned
            self.comparison = comparison
        }
    }

    static let rows: [Row] = [
        Row("Marc", "Marc", "marc"),
        Row("MARC", "MARC", "marc"),
        Row("Ma\u{200B}rc", "Marc", "marc"),
        Row("\u{200B}Marc\u{200B}", "Marc", "marc"),
        Row("\u{FEFF}Marc", "Marc", "marc"),
        Row("Ma\u{2060}rc", "Marc", "marc"),
        Row("Ma\u{200C}r\u{200D}c", "Marc", "marc"),
        Row("Ma\u{00AD}rc", "Marc", "marc"),
        Row("  Marc\t\n", "Marc", "marc"),
        Row("\u{00A0}Marc\u{00A0}", "Marc", "marc"),
        Row("\u{200B} Marc \u{FEFF}", "Marc", "marc"),
        Row("a b", "a b", "a b"),
        Row("Éric", "Éric", "éric"),
        Row("E\u{301}ric", "E\u{301}ric", "e\u{301}ric"),
        Row("", "", ""),
        Row("\u{200B}\u{FEFF} \u{2060}", "", "")
    ]

    @Test("Format characters and surrounding white space removed, case kept; then lower-cased", arguments: rows)
    func forms(row: Row) {
        #expect(PseudoNormalizer.cleaned(row.pseudo) == row.cleaned)
        #expect(PseudoNormalizer.comparisonForm(row.pseudo) == row.comparison)
    }

    /// Stored keys use the frozen account key (ADR 0013 §7): on a cleaned pseudo it is the comparison form.
    @Test("On a cleaned pseudo, the account key equals the comparison form", arguments: rows)
    func accountKeyOfACleanedPseudo(row: Row) {
        #expect(AccountKey.make(PseudoNormalizer.cleaned(row.pseudo)) == PseudoNormalizer.comparisonForm(row.pseudo))
    }

    @Test func matchesIgnoresCaseFormatCharactersAndSurroundingSpaceInBothOrders() {
        #expect(PseudoNormalizer.matches("Ma\u{200B}rc", "mARC"))
        #expect(PseudoNormalizer.matches("mARC", "Ma\u{200B}rc"))
        #expect(PseudoNormalizer.matches("Marc ", "\u{FEFF}marc"))
        #expect(!PseudoNormalizer.matches("Marc", "Marc2"))
        #expect(!PseudoNormalizer.matches("Ma rc", "Marc"))
    }

    @Test func accentsCompareCanonicallyAndStaySignificant() {
        #expect(PseudoNormalizer.matches("Élodie", "E\u{301}LODIE"))
        #expect(!PseudoNormalizer.matches("Élodie", "Elodie"))
    }
}
