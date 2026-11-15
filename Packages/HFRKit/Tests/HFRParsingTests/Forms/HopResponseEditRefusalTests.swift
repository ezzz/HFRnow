import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// #756: HFR's link-less refusal of an edit POST of another account's message (`W440c`).
@Suite("Hop response classifier: edit rights refusal")
struct HopResponseEditRefusalTests {
    private static let sentence = "Vous n'avez pas les droits pour éditer ce message !"
    private static let capture = "W440c-mp-edit-post-other-account-message-refused"

    @Test("W440c: a link-less .hop that refreshes to the thread is rejected with HFR's sentence under .write")
    func rejectedUnderWrite() throws {
        let response = try HopResponseParser.classify(html: Fixture.capture(Self.capture))
        #expect(response == HopResponse(kind: .rejected, message: Self.sentence))
    }

    @Test("The sentence is a write refusal only: before the alert form it stays unrecognized")
    func otherContextsUnchanged() throws {
        let prepare = try HopResponseParser.classify(html: Fixture.capture(Self.capture), context: .alertPrepare)
        #expect(prepare.kind == .unrecognized)
    }
}
