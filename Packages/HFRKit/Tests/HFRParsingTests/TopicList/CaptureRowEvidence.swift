import Foundation

/// Facts read from a captured list page with plain regexes, independent of SwiftSoup and of the parser under test.
///
/// The differential tests use them where the port deviates from the oracle on purpose, so the expected value never
/// comes from the code being checked (LESSONS 33).
struct CaptureRowEvidence {
    /// Raw HTML of each `<tr class="sujet ligne_booleen …">` row, in page order.
    let rows: [String]

    init(html: String) {
        rows = html.matches(of: Self.rowPattern).map { String($0.output) }
    }

    /// Text of the `sujetCase6` cell of row `index`, tags stripped, `&amp;` decoded, trimmed.
    func starterText(row index: Int) -> String? {
        guard let match = rows[index].firstMatch(of: Self.starterPattern) else { return nil }
        let stripped = String(match.output.1).replacing(Self.tagPattern, with: "").replacing("&amp;", with: "&")
        return Self.trimmingWhiteSpace(stripped)
    }

    /// Trims Unicode `White_Space` only: U+200B, which HFR inserts in long pseudos, is kept
    /// (Foundation's `whitespacesAndNewlines` strips it on Linux).
    static func trimmingWhiteSpace(_ text: String) -> String {
        let isSpace = { (character: Character) in character.unicodeScalars.allSatisfy(\.properties.isWhitespace) }
        return String(text.drop(while: isSpace).reversed().drop(while: isSpace).reversed())
    }

    /// Topic number of the title link's `title="Sujet n°<post>"`.
    func topicNumber(row index: Int) -> Int? {
        rows[index].firstMatch(of: Self.topicNumberPattern).flatMap { Int($0.output.1) }
    }

    /// Whether row `index` shows an image file named `sondage.gif` (in any folder).
    func showsPollIcon(row index: Int) -> Bool {
        rows[index].contains(Self.pollPattern)
    }

    // `Regex` is not `Sendable`; these literals capture only `Substring`s and are never mutated.
    nonisolated(unsafe) private static let rowPattern = /<tr class="sujet ligne_booleen.*?<\/tr>/.dotMatchesNewlines()
    nonisolated(unsafe) private static let starterPattern = /class="sujetCase6[^"]*">(.*?)<\/td>/.dotMatchesNewlines()
    nonisolated(unsafe) private static let tagPattern = /<[^>]*>/
    nonisolated(unsafe) private static let topicNumberPattern = /title="Sujet n°([0-9]+)"/
    nonisolated(unsafe) private static let pollPattern = /src="[^"]*\/sondage\.gif"/
}
