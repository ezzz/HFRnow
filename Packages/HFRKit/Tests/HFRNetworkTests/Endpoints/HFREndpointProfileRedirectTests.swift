import Foundation
import Testing
@testable import HFRNetwork

/// #714: `profilebdd.php`'s pseudo lookup and the member id its `301` names (HFR-PROTOCOL §6c "#714 — `profilebdd.php`
/// redirect"); the locations are those of `R716a`, `R716c` (`/hfr/profil-900002.htm`) and `R716d` (`/hfr/profil-.htm`).
struct HFREndpointProfileRedirectTests {
    private static let lookup = "https://forum.hardware.fr/profilebdd.php?config=hfr.inc&pseudo="

    @Test(arguments: [
        ("user2", "user2"),
        ("  user2 ", "user2"),
        ("user two", "user%20two"),
        ("a+b&c=d", "a%2Bb%26c%3Dd")
    ])
    func profileRedirectIsTheMPRowLinkNotFollowed(pseudo: String, encoded: String) throws {
        let request = try HFREndpoint.profileRedirect(pseudo: pseudo)
        #expect(request.url.absoluteString == Self.lookup + encoded)
        #expect(request.method == .get)
        #expect(request.redirectPolicy == .doNotFollow)
    }

    @Test(arguments: ["", " ", "\n\t"])
    func profileRedirectRefusesABlankPseudo(pseudo: String) {
        #expect(throws: NetworkError.self) { try HFREndpoint.profileRedirect(pseudo: pseudo) }
    }

    @Test(arguments: [
        (301, "/hfr/profil-900002.htm", 900002 as Int?),
        (302, "https://forum.hardware.fr/hfr/profil-12.htm", 12),
        (301, "/hfr/profil-.htm", nil),
        (301, "/hfr/profil-12a.htm", nil),
        (301, "/hfr/profil-12.htm?x=1", nil),
        (301, "/hfr/profil-12.html", nil),
        (301, "/forum2.php?config=hfr.inc", nil),
        (301, "https://evil.example/hfr/profil-12.htm", nil),
        (301, "http://forum.hardware.fr/hfr/profil-12.htm", nil),
        (301, "https://forum.hardware.fr:8443/hfr/profil-12.htm", nil),
        (301, "/hfr/profil-99999999999999999999.htm", nil),
        (200, "/hfr/profil-12.htm", nil),
        (301, "", nil)
    ])
    func memberIDIsReadFromTheRedirectOnly(status: Int, location: String, expected: Int?) throws {
        let url = try #require(URL(string: Self.lookup + "user2"))
        let response = HTTPResponse(statusCode: status, headers: ["Location": location], url: url)
        #expect(HFREndpoint.memberID(inProfileRedirect: response) == expected)
    }
}
