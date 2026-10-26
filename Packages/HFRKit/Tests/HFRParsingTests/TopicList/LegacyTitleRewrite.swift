/// The "TU" rewrite legacy applies in `Topic -setATitle:` (`Topic.m:90-94`, `RangeOfCharacters.m:330-343`).
///
/// The port keeps the raw title (LOT-010: the rewrite is a presentation concern). The differential tests apply this
/// copy to the parsed title before comparing it with the oracle, so the comparison still covers every title.
enum LegacyTitleRewrite {
    // `Regex` is not `Sendable`; these are built once from literals and never mutated.
    /// Replacements in legacy order, each a case-insensitive literal match.
    nonisolated(unsafe) private static let spellings: [Regex<Substring>] = [
        "topic unique", "T.U.", "topik unique", "toupik ounik", "topique unique",
        "topic unik", "topik unik", "topic officiel", "TOPIKUNIK"
    ].map { Regex(verbatim: $0).ignoresCase() }

    /// The title as legacy stored it.
    static func filterTU(_ title: String) -> String {
        spellings.reduce(title) { result, spelling in result.replacing(spelling, with: "TU") }
    }
}
