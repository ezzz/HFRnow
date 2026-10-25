import Foundation
import Testing
@testable import HFRModels

@Suite struct HopResponseTests {
    @Test func roundTripsWithRefreshData() throws {
        let response = HopResponse(
            kind: .success,
            message: "Votre message a été ajouté",
            refreshURL: URL(string: "https://forum.hardware.fr/forum2.php?cat=13&post=1"),
            refreshAnchor: "t55"
        )
        #expect(try roundTrip(response) == response)
    }

    @Test func kindsAreDistinctAndEncodeAsWords() throws {
        let kinds: [HopResponse.Kind] = [.success, .rejected, .loggedOut, .alreadyAlerted, .unrecognized]
        #expect(Set(kinds).count == 5)
        #expect(try text(of: JSONEncoder().encode(kinds))
            == #"["success","rejected","loggedOut","alreadyAlerted","unrecognized"]"#)
    }

    @Test func kindParticipatesInEquality() {
        #expect(HopResponse(kind: .success) != HopResponse(kind: .unrecognized))
    }
}
