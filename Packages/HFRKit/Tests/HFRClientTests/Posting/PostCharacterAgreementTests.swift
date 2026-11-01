import HFRModels
import Testing
@testable import HFRClient

/// LOT-096: the posting flow (LOT-048) refuses exactly what `PostCharacterCheck` says truncates, on the same texts, and
/// sends the untested BMP emoji.
@Suite("Posting flow and the character check agree")
struct PostCharacterAgreementTests {
    @Test(
        "The refused characters are the truncating ones",
        arguments: ["before 😀 after 😀 and 👍🏽", "family 👨‍👩‍👧 flag 🇫🇷 ❤️", "𝟙 ☺ 🎉 ✌", "keycap 1️⃣ then 🤪"]
    )
    func refusedAreTruncating(text: String) async throws {
        let outcome = try await PostingHarness.run(form: "R47b") { flow, form async throws(PostingError) in
            try await flow.reply(text, with: form)
        }
        #expect(outcome.error == .unsupportedCharacters(.text, PostCharacterCheck.truncatingCharacters(in: text)))
        #expect(outcome.post == nil)
    }

    @Test("Untested BMP emoji are sent", arguments: ["é ☺ ❤ kept", "❤️ and ✌️ and 1️⃣", "™ ©"])
    func untestedAreSent(text: String) async throws {
        #expect(PostCharacterCheck.truncatingCharacters(in: text).isEmpty)
        let outcome = try await PostingHarness.run(form: "R47b") { flow, form async throws(PostingError) in
            try await flow.reply(text, with: form)
        }
        #expect(outcome.post != nil)
    }
}
