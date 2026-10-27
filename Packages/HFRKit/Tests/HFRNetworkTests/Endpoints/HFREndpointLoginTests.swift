import Foundation
import Testing
@testable import HFRNetwork

struct HFREndpointLoginTests {
    private static func body(_ request: HTTPRequest) -> String {
        request.body.flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
    }

    @Test func loginPostsTheLegacyFieldsInOrder() throws {
        let request = try HFREndpoint.login(pseudo: "user2", password: "fake")
        #expect(request.method == .post)
        #expect(request.url.absoluteString == "https://forum.hardware.fr/login_validation.php?config=hfr.inc")
        #expect(request.headers["Content-Type"] == FormBody.contentType)
        #expect(Self.body(request) == "pseudo=user2&password=fake&action=send&login=Se+connecter")
    }

    /// Values are sent as given: no trimming, every reserved or non-ASCII byte percent-encoded.
    @Test func loginEncodesValuesAsGiven() throws {
        let request = try HFREndpoint.login(pseudo: " Éric&co ", password: "a+b=c %")
        #expect(Self.body(request).hasPrefix("pseudo=+%C3%89ric%26co+&password=a%2Bb%3Dc+%25&action=send&"))
    }
}
