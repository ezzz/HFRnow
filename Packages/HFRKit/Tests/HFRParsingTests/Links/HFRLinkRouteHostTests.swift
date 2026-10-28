import Foundation
import Testing
@testable import HFRParsing

/// Only `forum.hardware.fr` is routed (LESSONS 37, 43): everything else is `.external`, whatever its path looks like.
@Suite("Link router hosts")
struct HFRLinkRouteHostTests {
    static let path = "/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t75482227"

    @Test("Lookalike hosts, user info, ports and other schemes are refused", arguments: [
        "https://forum.hardware.fr.evil.example/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t75482227",
        "https://evilforum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t75482227",
        "https://hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t75482227",
        "https://www.forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t75482227",
        "https://forum.hardware.fr-evil.example/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t75482227",
        "https://evil.example/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t75482227",
        "https://forum.hardware.fr./hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t75482227",
        "https://forum.hardware.fr@evil.example/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t75482227",
        "https://forum.hardware.fr:pw@evil.example/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t75482227",
        "https://user@forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t75482227",
        "https://user:pw@forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t75482227",
        "https://forum.hardware.fr:443/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t75482227",
        "https://forum.hardware.fr:8443/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t75482227",
        "http://forum.hardware.fr:80/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t75482227",
        "http://forum.hardware.fr:8080/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t75482227",
        "https://forum.hardware.fr%2eevil.example/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t75482227",
        "ftp://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t75482227",
        "hfrnow://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t75482227",
        "https://evil.example/?u=https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t75482227",
        "javascript:alert(1)",
        "mailto:forum@hardware.fr",
        "file:///hfr/Discussions/liste_sujet-1.htm",
        "https:forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t75482227",
        "//forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t75482227",
        "/hfr/Discussions/liste_sujet-1.htm",
        "forum2.php?cat=13&post=1",
        "",
        "https://",
        "https://forum.hardware.fr\\@evil.example/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t75482227"
    ])
    func refused(link: String) throws {
        // Some of these are not valid `URL`s on every platform: an invalid string cannot reach the router at all.
        guard let url = URL(string: link) else { return }
        #expect(HFRLinkRoute.route(for: url) == .external(url), "\(link)")
    }

    @Test("The router keeps the original URL in `.external`, so the app can hand it to the system browser")
    func externalKeepsURL() throws {
        let url = try #require(URL(string: "https://example.org/a?b=c#d"))
        #expect(HFRLinkRoute.route(for: url) == .external(url))
    }

    @Test("Host case and an empty port are the same origin", arguments: [
        "https://FORUM.HARDWARE.FR/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t75482227",
        "https://forum.hardware.fr:/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm#t75482227"
    ])
    func accepted(link: String) throws {
        let url = try #require(URL(string: link))
        guard case .topic = HFRLinkRoute.route(for: url) else {
            Issue.record("\(link) is the forum origin")
            return
        }
    }
}
