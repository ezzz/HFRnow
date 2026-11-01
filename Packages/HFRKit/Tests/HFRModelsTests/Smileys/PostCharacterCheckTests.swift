import Testing
@testable import HFRModels

/// Characters HFR cuts a post at (Q-3, `W12`) and BMP emoji whose fate is not captured (CAP-N3, #171).
@Suite struct PostCharacterCheckTests {
    @Test(
        "A scalar above U+FFFF truncates, whatever the grapheme around it",
        arguments: ["😀", "👍🏽", "👨‍👩‍👧", "🇫🇷", "𝟙", "❤️‍🔥", "🎉"] as [Character]
    )
    func truncates(character: Character) {
        #expect(PostCharacterCheck.risk(of: character) == .truncates)
    }

    @Test(
        "An emoji inside the BMP, or with U+FE0F, is untested: not refused",
        arguments: ["❤", "❤\u{FE0F}", "☺", "☹", "✌", "1\u{FE0F}\u{20E3}", "1\u{20E3}", "#\u{20E3}", "™", "♥", "↔", "⚠"] as [Character]
    )
    func untested(character: Character) {
        #expect(PostCharacterCheck.risk(of: character) == .untested)
    }

    @Test(
        "Plain text has no risk, Latin-1 emoji-like characters included",
        arguments: ["a", "é", "œ", "€", "1", "#", "©", "®", " "] as [Character]
    )
    func plain(character: Character) {
        #expect(PostCharacterCheck.risk(of: character) == nil)
    }

    @Test func riskyCharactersAreListedOnceInOrder() {
        let found = PostCharacterCheck.riskyCharacters(in: "a😀 ❤ b 😀 👍🏽 ❤ é")
        #expect(found == [
            RiskyCharacter(character: "😀", risk: .truncates),
            RiskyCharacter(character: "❤", risk: .untested),
            RiskyCharacter(character: "👍🏽", risk: .truncates)
        ])
        #expect(PostCharacterCheck.truncatingCharacters(in: "a😀 ❤ b 😀 👍🏽 ❤ é") == ["😀", "👍🏽"])
        #expect(PostCharacterCheck.riskyCharacters(in: "").isEmpty)
    }
}
