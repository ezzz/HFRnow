import Foundation
import HFRModels
import Testing

@Suite("TopicTitle (legacy filterTU, #818)")
struct TopicTitleTests {
    /// The nine spellings of `RangeOfCharacters.m:330-343` @ 87fe0d1c, in legacy order, each in a bracketed title.
    @Test("every spelling becomes TU", arguments: [
        "topic unique", "T.U.", "topik unique", "toupik ounik", "topique unique",
        "topic unik", "topik unik", "topic officiel", "TOPIKUNIK"
    ])
    func spelling(_ spelling: String) {
        #expect(TopicTitle.displayed("[\(spelling)] Diablo IV") == "[TU] Diablo IV")
    }

    @Test("matching ignores case")
    func caseInsensitive() {
        #expect(TopicTitle.displayed("[Topic Unique] Diablo IV") == "[TU] Diablo IV")
        #expect(TopicTitle.displayed("[TOPIC UNIQUE] x") == "[TU] x")
        #expect(TopicTitle.displayed("[t.u.] x") == "[TU] x")
    }

    @Test("a spelling at the end, and several in one title")
    func position() {
        #expect(TopicTitle.displayed("Diablo IV topic unique") == "Diablo IV TU")
        #expect(TopicTitle.displayed("topic unique / Topik Unik") == "TU / TU")
    }

    @Test("the dots of T.U. are literal")
    func literalDots() {
        #expect(TopicTitle.displayed("TxUx and TAUB") == "TxUx and TAUB")
    }

    @Test("a title with no match is unchanged, spacing included")
    func noMatch() {
        #expect(TopicTitle.displayed("[Topic Unique]  double  space") == "[TU]  double  space")
        #expect(TopicTitle.displayed("Topic Unica") == "Topic Unica")
        #expect(TopicTitle.displayed("") == "")
    }

    @Test("idempotent")
    func idempotent() {
        let once = TopicTitle.displayed("[Topic Unique] Diablo IV")
        #expect(TopicTitle.displayed(once) == once)
    }
}
