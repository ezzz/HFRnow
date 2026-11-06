import Foundation
import Testing
@testable import HFRParsing

/// #383: HFR's answer to a jar whose `md_passs` it refuses (`R70a`–`R70d`), told apart from every other captured page.
@Suite("Stale-session notice")
struct StaleSessionNoticeParserTests {
    private static let profilePage1 = URL(string: "https://forum.hardware.fr/user/editprofil.php?config=hfr.inc&page=1")
        ?? HFRURL.base

    @Test("The four stale-session captures are recognized at the URL each was served at", arguments: [
        ("R70a-home-stale-session", "https://forum.hardware.fr/"),
        ("R70b-favourites-owntopic1-stale-session", "https://forum.hardware.fr/forum1f.php?config=hfr.inc&owntopic=1"),
        ("R70c-profile-edit-page1-stale-session", "https://forum.hardware.fr/user/editprofil.php?config=hfr.inc&page=1"),
        ("R70d-profile-edit-page5-stale-session", "https://forum.hardware.fr/user/editprofil.php?config=hfr.inc&page=5")
    ])
    func staleSessionCaptures(file: String, url: String) throws {
        let html = try Fixture.capture(file)
        let requestURL = try #require(URL(string: url))
        #expect(try StaleSessionNoticeParser.isStaleSessionNotice(html: html, requestURL: requestURL))
    }

    /// Every other page of the corpus, `.hop` pages included (the cookie-less "Mot de passe incorrect !" of `R71a` and
    /// `R71b`, the logged-out `R12`, the token-echoing `W17c`, write confirmations), is not the stale-session page.
    @Test("No other capture of the corpus is the stale-session page")
    func noOtherCapture() throws {
        let directory = try #require(Bundle.module.url(forResource: "captures", withExtension: nil, subdirectory: "Fixtures"))
        let pages = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".html") }
        #expect(pages.count > 100)
        var recognized: [String] = []
        for page in pages {
            let html = Fixture.decoded(try Data(contentsOf: directory.appending(path: page)))
            if (try? StaleSessionNoticeParser.isStaleSessionNotice(html: html, requestURL: Self.profilePage1)) == true {
                recognized.append(page)
            }
        }
        #expect(recognized.sorted() == [
            "R70a-home-stale-session.html", "R70b-favourites-owntopic1-stale-session.html",
            "R70c-profile-edit-page1-stale-session.html", "R70d-profile-edit-page5-stale-session.html"
        ])
    }

    @Test("The cookie-less profile pages stay unrecognized: other sentence, refresh to login.php", arguments: [
        "R71a-profile-edit-page5-anon", "R71b-profile-edit-page1-anon"
    ])
    func cookielessProfilePages(file: String) throws {
        #expect(try !StaleSessionNoticeParser.isStaleSessionNotice(html: try Fixture.capture(file), requestURL: Self.profilePage1))
    }

    /// `R70c` with one part changed: the sentence and the refresh target must both match, whatever the page's size.
    @Test("A variant of the stale page differing in the sentence, the block or the target is not recognized", arguments: [
        ("Identifiants invalides !", "Mot de passe incorrect !"),
        ("Identifiants invalides !", "Identifiants invalides ! Réessayez"),
        ("Identifiants invalides !", "Identifiants invalides ! <a href=\"/login.php?config=hfr.inc\">Retour</a>"),
        ("Identifiants invalides !", "Identifiants invalides ! <input type=\"hidden\" name=\"x\" value=\"1\" />"),
        ("<div class=\"hop\">", "<div class=\"hop\">Identifiants invalides !</div><div class=\"hop\">"),
        ("url=/unlog.php?config=hfr.inc", "url=../login.php?config=hfr.inc"),
        ("url=/unlog.php?config=hfr.inc", "url=/unlog.php?config=hfr.inc&codehex=1"),
        ("url=/unlog.php?config=hfr.inc", "url=/unlog.php"),
        ("url=/unlog.php?config=hfr.inc", "url=/unlog.php?config=hfr.inc#top"),
        ("url=/unlog.php?config=hfr.inc", "url=https://example.com/unlog.php?config=hfr.inc"),
        ("url=/unlog.php?config=hfr.inc", "url=https://forum.hardware.fr:8443/unlog.php?config=hfr.inc"),
        ("url=/unlog.php?config=hfr.inc", "url=/user/unlog.php?config=hfr.inc"),
        // A target spelled with a character reference is not the captured page (the raw pre-filter, conservative side).
        ("url=/unlog.php?config=hfr.inc", "url=/unlog&#46;php?config=hfr.inc"),
        ("<meta http-equiv=\"Refresh\" content=\"1; url=/unlog.php?config=hfr.inc\" />", ""),
        (
            "<meta http-equiv=\"Refresh\" content=\"1; url=/unlog.php?config=hfr.inc\" />",
            "<meta http-equiv=\"Refresh\" content=\"1; url=/unlog.php?config=hfr.inc\" />"
                + "<meta http-equiv=\"Refresh\" content=\"0; url=/login.php?config=hfr.inc\" />"
        )
    ])
    func variants(original: String, replacement: String) throws {
        let html = try Fixture.capture("R70c-profile-edit-page1-stale-session")
        try #require(html.contains(original))
        let variant = html.replacing(original, with: replacement, maxReplacements: 1)
        #expect(try !StaleSessionNoticeParser.isStaleSessionNotice(html: variant, requestURL: Self.profilePage1))
    }

    @Test("The same sentence and target with other whitespace, or the target written absolute, is recognized")
    func equivalentSpellings() throws {
        let html = try Fixture.capture("R70c-profile-edit-page1-stale-session")
        for (original, replacement) in [
            ("Identifiants invalides !", "\n  Identifiants\tinvalides   !\n"),
            ("url=/unlog.php?config=hfr.inc", "url=https://forum.hardware.fr/unlog.php?config=hfr.inc")
        ] {
            let variant = html.replacing(original, with: replacement, maxReplacements: 1)
            #expect(try StaleSessionNoticeParser.isStaleSessionNotice(html: variant, requestURL: Self.profilePage1))
        }
    }
}
