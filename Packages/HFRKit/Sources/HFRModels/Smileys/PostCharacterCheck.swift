/// What HFR does with a character of a post, as far as it is captured (LOT-096).
public enum PostCharacterRisk: Sendable, Hashable {
    /// HFR cuts the post at it: the character holds a scalar above U+FFFF (Q-3, `W12`). LOT-048 refuses it.
    case truncates
    /// A character with the Unicode `Emoji` property inside the BMP (`❤`, `☺`, a keycap), text-default symbols included
    /// (`™`, `♥`, `↔`, `✔`, `⚠`…): kept, replaced or cut is not captured (CAP-N3, #171). Never refused; warn only where
    /// `EmojiSmileyTable` has a suggestion, until CAP-N3 answers.
    case untested
}

/// A character of a post with its risk.
public struct RiskyCharacter: Sendable, Hashable {
    /// The character (a whole grapheme: `👨‍👩‍👧` is one).
    public let character: Character
    /// What HFR does with it.
    public let risk: PostCharacterRisk

    /// Creates a risky character.
    public init(character: Character, risk: PostCharacterRisk) {
        self.character = character
        self.risk = risk
    }
}

/// Finds the characters of a post HFR cuts, or might cut (LOT-096). `PostingFlow` (LOT-048) refuses `truncates` ones.
public enum PostCharacterCheck {
    /// The risk of `character`, nil when there is none known: a scalar above U+FFFF truncates; otherwise a variation
    /// selector U+FE0F, a keycap mark U+20E3 or an emoji scalar beyond Latin-1 (`isEmoji`; `#`, digits, `©` and `®`,
    /// which Unicode also counts, stay plain text) is untested.
    public static func risk(of character: Character) -> PostCharacterRisk? {
        let scalars = character.unicodeScalars
        if scalars.contains(where: { $0.value > 0xFFFF }) { return .truncates }
        let marks: Set<UInt32> = [0xFE0F, 0x20E3]
        if scalars.contains(where: { marks.contains($0.value) || ($0.value > 0xFF && $0.properties.isEmoji) }) { return .untested }
        return nil
    }

    /// The risky characters of `text`, each once, in the order they first appear.
    public static func riskyCharacters(in text: String) -> [RiskyCharacter] {
        var found: [RiskyCharacter] = []
        for character in text where !found.contains(where: { $0.character == character }) {
            if let risk = risk(of: character) { found.append(RiskyCharacter(character: character, risk: risk)) }
        }
        return found
    }

    /// The characters HFR cuts a post at, each once, in order: what LOT-048 refuses.
    public static func truncatingCharacters(in text: String) -> [Character] {
        riskyCharacters(in: text).filter { $0.risk == .truncates }.map(\.character)
    }
}
