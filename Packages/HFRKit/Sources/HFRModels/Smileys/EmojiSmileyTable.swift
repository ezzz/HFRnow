import Foundation

/// The catalogue smileys to suggest for an emoji (LOT-096, FEAT-012 proposed by Bybifok).
///
/// HFR cuts a post at its first non-BMP character (Q-3, `W12`), so the app refuses such characters (LOT-048) and can
/// offer the HFR smiley that says the same thing instead. Legacy had no table: it removed U+1D000-1F77F and
/// U+2100-26FF from a post without a word (`removeEmoji`, `RangeOfCharacters.m:306-328`, `AddMessageViewController.m:553`
/// at `2440d79`). The bundled table (`EmojiSmileys.json`) maps an emoji to codes of the bundled catalogue
/// (`CommonSmileys.json`, LOT-012), best first; it only uses smileys whose file name says what they show (`smile`,
/// `cry`, `mad`…).
public struct EmojiSmileyTable: Sendable, Hashable {
    /// Smiley codes keyed by emoji, the key without variation selector or skin tone.
    public let suggestions: [String: [String]]

    /// Creates a table; keys are normalised like a looked-up emoji, and two keys that become one (`❤` and `❤️`) merge
    /// their codes, in key order, each code once.
    public init(suggestions: [String: [String]]) {
        var normalized: [String: [String]] = [:]
        for (emoji, codes) in suggestions.sorted(by: { $0.key < $1.key }) {
            let key = Self.key(of: emoji)
            for code in codes where !(normalized[key]?.contains(code) ?? false) {
                normalized[key, default: []].append(code)
            }
        }
        self.suggestions = normalized
    }

    /// The table shipped with the module.
    public static func bundled() throws -> EmojiSmileyTable {
        guard let location = Bundle.module.url(forResource: "EmojiSmileys", withExtension: "json") else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try decode(Data(contentsOf: location))
    }

    /// Decodes a table from JSON data (the bundled file's format: `[{"emoji": "🙂", "smileys": [":)"]}]`).
    public static func decode(_ data: Data) throws -> EmojiSmileyTable {
        let entries = try JSONDecoder().decode([Entry].self, from: data)
        var suggestions: [String: [String]] = [:]
        for entry in entries {
            suggestions[entry.emoji, default: []].append(contentsOf: entry.smileys)
        }
        return EmojiSmileyTable(suggestions: suggestions)
    }

    /// The smiley codes to suggest for `character`, best first; empty when the table has none. A variation selector
    /// (U+FE0E, U+FE0F) and a skin tone (U+1F3FB-1F3FF) do not change the answer: `❤️` is `❤`, `👋🏽` is `👋`.
    public func smileys(for character: Character) -> [String] {
        suggestions[Self.key(of: String(character))] ?? []
    }

    // MARK: Internals

    private struct Entry: Decodable {
        let emoji: String
        let smileys: [String]
    }

    /// The emoji without variation selectors and skin tones.
    static func key(of emoji: String) -> String {
        String(String.UnicodeScalarView(emoji.unicodeScalars.filter { scalar in
            !(scalar.value == 0xFE0E || scalar.value == 0xFE0F || (0x1F3FB...0x1F3FF).contains(scalar.value))
        }))
    }
}
