import Foundation
import Testing
@testable import HFRModels

/// The bundled emoji → smiley table (LOT-096): every suggestion is a catalogue code, lookups ignore U+FE0F and skin tones.
@Suite struct EmojiSmileyTableTests {
    @Test func everySuggestedCodeIsInTheBundledCatalogue() throws {
        let table = try EmojiSmileyTable.bundled()
        let codes = Set(try CommonSmileyCatalog.bundled().map(\.code))
        #expect(!table.suggestions.isEmpty)
        for (emoji, smileys) in table.suggestions {
            #expect(!smileys.isEmpty, "\(emoji)")
            #expect(Set(smileys).isSubset(of: codes), "\(emoji): \(smileys)")
            #expect(Set(smileys).count == smileys.count, "\(emoji): \(smileys)")
        }
    }

    @Test func everyKeyIsOneEmojiWithoutSelectorOrSkinTone() throws {
        for emoji in try EmojiSmileyTable.bundled().suggestions.keys {
            #expect(emoji.count == 1, "\(emoji)")
            #expect(EmojiSmileyTable.key(of: emoji) == emoji, "\(emoji)")
            #expect(emoji.unicodeScalars.contains { $0.properties.isEmoji }, "\(emoji)")
        }
    }

    @Test(
        "A variation selector or a skin tone does not change the suggestion",
        arguments: [
            ("❤", [":love:"]), ("❤\u{FE0F}", [":love:"]), ("☺\u{FE0F}", [":)"]), ("☹\u{FE0E}", [":("]),
            ("👋", [":hello:"]), ("👋🏽", [":hello:"]), ("🤪", [":crazy:", ":fou:"]), ("😀", [":D"])
        ] as [(Character, [String])]
    )
    func lookup(character: Character, smileys: [String]) throws {
        #expect(try EmojiSmileyTable.bundled().smileys(for: character) == smileys)
    }

    @Test("An emoji or a character without an entry has no suggestion", arguments: ["🦄", "a", "é", "1", "👨‍👩‍👧"] as [Character])
    func noSuggestion(character: Character) throws {
        #expect(try EmojiSmileyTable.bundled().smileys(for: character).isEmpty)
    }

    @Test func keysAreNormalisedAndMergedEachCodeOnce() throws {
        let table = EmojiSmileyTable(suggestions: ["❤\u{FE0F}": [":love:"], "❤": [":love:", ":ange:"]])
        #expect(table.suggestions == ["❤": [":love:", ":ange:"]])
        let decoded = try EmojiSmileyTable.decode(Data(#"[{"emoji": "👋🏽", "smileys": [":hello:"]}]"#.utf8))
        #expect(decoded.smileys(for: "👋") == [":hello:"])
    }
}
