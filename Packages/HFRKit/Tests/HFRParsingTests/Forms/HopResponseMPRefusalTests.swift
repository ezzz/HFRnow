import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// LOT-058: the two private-message refusals only a `.hop` shape tells from a success (#507, #137).
@Suite("Hop response: MP refusals")
struct HopResponseMPRefusalTests {
    @Test("W76: an unknown pseudo in newdest is a refusal, with HFR's sentence, without the back link and without a refresh")
    func unknownPseudo() throws {
        let response = try HopResponseParser.classify(html: Fixture.capture("W76-mp-group-reply-unknown-pseudo-refused"))
        #expect(response == HopResponse(kind: .rejected, message: "Désolé, le pseudo suivant n'existe pas : zqzhbhvwyigjqt"))
    }

    @Test(
        "W137a, W137b: nonlu.php without a session, the bytes of a thread the account cannot see (R96c), is a refusal",
        arguments: ["W137a-mp-mark-unread-logged-out", "W137b-mp-mark-unread-logged-out-again"]
    )
    func markUnreadWithoutSession(name: String) throws {
        let page = try Fixture.capture(name)
        #expect(page == (try Fixture.capture("R96c-mp-thread-owner-after-thread-delete")))
        #expect(try HopResponseParser.classify(html: page) == HopResponse(
            kind: .rejected, message: "Ce message ne vous est pas destiné, désolé"
        ))
    }
}
