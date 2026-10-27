import Foundation
import Testing
@testable import HFRParsing

@Suite("Search redirect parser")
struct SearchRedirectParserTests {
    @Test("R50a waiting page: refresh target, &amp; decoded, resolved against the forum")
    func capturedWaitingPage() throws {
        let html = try Fixture.capture("R50a-search-post-waiting-page")
        let url = try SearchRedirectParser.redirectURL(in: html)
        #expect(url.absoluteString == "https://forum.hardware.fr/forum1.php?recherches=1&cat=13&orderSearch=0&config=hfr.inc"
            + "&pseud=&search=pizza+napolitaine&titre=3&jour=&mois=&annee=&resSearch=200&daterange=2&subcat=0"
            + "&searchtype=1&trash=0&trash_post=0&moderation=0")
        #expect(HFRURL.queryValue(named: "recherches", in: url.absoluteString) == "1")
    }

    @Test("R50c results page has no refresh: missing element")
    func resultsPageHasNoRefresh() throws {
        let html = try Fixture.capture("R50c-search-no-result-no-cookie")
        #expect(throws: ParsingError.missingElement("meta http-equiv=refresh")) {
            try SearchRedirectParser.redirectURL(in: html)
        }
    }

    @Test("Other metas are ignored; quotes, case and comma separator accepted")
    func variants() throws {
        let html = """
            <html><head><meta http-equiv="Expires" content="0"><META HTTP-EQUIV="REFRESH" content="0, URL='/forum1.php?a=1&amp;b=2'">
            </head><body></body></html>
            """
        #expect(try SearchRedirectParser.redirectURL(in: html).absoluteString == "https://forum.hardware.fr/forum1.php?a=1&b=2")
    }

    @Test("A refresh without target is skipped", arguments: ["5", "5;", "5; url=", "url=/x"])
    func noTarget(content: String) {
        let html = "<html><head><meta http-equiv=\"refresh\" content=\"\(content)\"></head></html>"
        #expect(throws: ParsingError.missingElement("meta http-equiv=refresh")) {
            try SearchRedirectParser.redirectURL(in: html)
        }
    }

    @Test(
        "Targets off the forum or with another scheme are refused",
        arguments: ["javascript:alert(1)", "https://evil.example/forum1.php", "//evil.example/x", "https://forum.hardware.fr@evil.example/",
                  "http://forum.hardware.fr:80/forum1.php?recherches=1"]
    )
    func refusedTargets(target: String) {
        let html = "<html><head><meta http-equiv=\"refresh\" content=\"1; url=\(target)\"></head></html>"
        #expect(throws: ParsingError.invalidValue(field: "search redirect URL")) {
            try SearchRedirectParser.redirectURL(in: html)
        }
    }

    @Test("An explicit https port on the forum is accepted")
    func explicitHTTPSPort() throws {
        let html = "<meta http-equiv=\"refresh\" content=\"1; url=https://forum.hardware.fr:443/forum1.php?recherches=1\">"
        let url = try SearchRedirectParser.redirectURL(in: html)
        #expect(url.scheme == "https")
        #expect(url.host(percentEncoded: false) == "forum.hardware.fr")
    }

    @Test("http to the forum is upgraded to https")
    func upgrade() throws {
        let html = "<meta http-equiv=\"refresh\" content=\"1; url=http://forum.hardware.fr/forum1.php?recherches=1\">"
        #expect(try SearchRedirectParser.redirectURL(in: html).scheme == "https")
    }
}
