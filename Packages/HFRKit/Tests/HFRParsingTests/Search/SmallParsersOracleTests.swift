import Foundation
import Testing
@testable import HFRParsing

/// Differential tests (ADR 0004) of the LOT-025 parsers against the LOT-005 legacy oracles, on the same captures.
/// Each test compares the whole result; deviations from legacy are asserted as such and listed in
/// `docs/lots/LOT-025-small-parsers.md` ("Intentional differences").
@Suite("Small parsers against the legacy oracles")
struct SmallParsersOracleTests {
    static let searchCases = ["R50a", "R50b", "R50c"]
    static let profileCases = ["R55-p1", "R55-p3", "R55-p5", "R55-p5u1"]
    static let smileySearchCases = ["R53a", "R53b", "R53c"]
    static let wikiCases = ["R54"]

    @Test("the case lists cover every LOT-005 case of these kinds")
    func casesCoverTheMap() throws {
        let kinds: Set = ["search-redirect", "profile-edit", "smiley-search", "smiley-keywords"]
        let tested = Set(Self.searchCases + Self.profileCases + Self.smileySearchCases + Self.wikiCases)
        #expect(try Lot005Oracle.mappedCases(ofKinds: kinds) == tested)
    }

    // MARK: - Search redirect

    @Test("redirect: found or not, and the URL, equal the legacy result", arguments: searchCases)
    func searchRedirect(id: String) throws {
        let oracle = try Lot005Oracle.load(id)
        let legacy = oracle.result
        if legacy["hasRedirect"] as? Bool == true {
            let url = try SearchRedirectParser.redirectURL(in: oracle.html)
            #expect(url.absoluteString == legacy["absoluteURL"] as? String)
            // Legacy `relativeURL` is path + raw query + fragment of the absolute URL.
            let relative = url.path + (url.query.map { "?" + $0 } ?? "") + (url.fragment.map { "#" + $0 } ?? "")
            #expect(relative == legacy["relativeURL"] as? String)
            #expect(legacy["error"] is NSNull)
        } else {
            // Legacy: no refresh means the error "Aucune page de résultats n'a été trouvée." (code -2).
            #expect(throws: ParsingError.missingElement("meta http-equiv=refresh")) {
                try SearchRedirectParser.redirectURL(in: oracle.html)
            }
            let error = try #require(legacy["error"] as? [String: Any])
            #expect(error["code"] as? Int == -2)
            #expect(legacy["absoluteURL"] is NSNull)
        }
    }

    // MARK: - Profile edit page

    @Test("profile: token length equals the legacy match; avatar equals legacy only where legacy was right", arguments: profileCases)
    func profileEdit(id: String) throws {
        let oracle = try Lot005Oracle.load(id)
        let legacy = oracle.result
        #expect(legacy["outcome"] as? String == "success")
        let page = try ProfileEditPageParser.parse(oracle.html)
        // The oracle hides the token behind a placeholder and records its length (the captures hold `REDACTED`).
        #expect(page.hashCheck.count == legacy["hashLength"] as? Int)
        let requests = try #require(legacy["requests"] as? [[String: Any]])
        let legacyAvatar = try #require(requests.last?["url"] as? String)
        if id == "R55-p5u1" {
            #expect(page.avatarURL?.absoluteString == legacyAvatar)
            #expect(legacyAvatar == "https://forum-images.hardware.fr/images/mesdiscussions-900001.jpg")
        } else {
            // Legacy quirk Q1: the first image after any `profilCase3` (an icon, a tracking pixel) was fetched as the avatar.
            #expect(page.avatarURL == nil)
            #expect(legacyAvatar.hasSuffix("/aide.gif") || legacyAvatar.contains("matomo.php"))
        }
    }

    // MARK: - Smiley search

    @Test("smiley search: the whole list equals the live service and the legacy callback", arguments: smileySearchCases)
    func smileySearch(id: String) throws {
        let oracle = try Lot005Oracle.load(id)
        let live = try #require(oracle.result["live"] as? [String: Any])
        let legacy = try #require(oracle.result["legacy"] as? [String: Any])
        let liveSmileys = try #require(live["smileys"] as? [[String: Any]])
        let legacyItems = try #require(legacy["items"] as? [[String: Any]])

        let smileys = try SmileySearchParser.parse(oracle.html)
        let expectedLive = liveSmileys.map { smiley -> [String] in
            let source = (smiley["imageSource"] as? [String: String])?["remote"] ?? ""
            return [smiley["code"] as? String ?? "", source]
        }
        let expectedLegacy = legacyItems.map { [$0["code"] as? String ?? "", $0["source"] as? String ?? ""] }
        let actual = smileys.map { [$0.code, $0.url.absoluteString] }
        #expect(actual == expectedLive)
        #expect(actual == expectedLegacy)
        #expect((legacy["noResult"] as? Int == 1) == smileys.isEmpty)
    }

    // MARK: - Smiley wiki

    @Test("wiki: keywords equal the Objective-C step and the Swift copy", arguments: wikiCases)
    func wikiKeywords(id: String) throws {
        let oracle = try Lot005Oracle.load(id)
        let objc = try #require(oracle.result["legacyObjC"] as? [String: Any])
        let swiftApp = try #require(oracle.result["swiftApp"] as? [String: Any])
        let detail = try SmileyWikiDetailParser.parse(oracle.html)
        #expect(detail.keywords == objc["arrCodeList"] as? [String])
        #expect(detail.keywords == swiftApp["keywords"] as? [String])
        #expect(detail.code == oracle.context["code"] as? String)
        #expect(detail.keywords.joined(separator: " ") == objc["value"] as? String)
    }
}
