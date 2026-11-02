import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// #306 against the legacy oracle (#268): `result.fastAnswer` is what legacy's reader set in `setupFastAnswer:`
/// (`HFRswift/Wrapped/MessagesTableViewController.m:1556-1583` at `2440d79`): `isFavoritesOrRead`, the first `href` of the body
/// containing `delflag` (else `nonlu`), and `isRedFlagged`, that link holds `flagn0.gif`.
///
/// The two readings are compared where they read the same link: the function-bar link is also the first `delflag` href of the
/// page. Everywhere else the difference is intentional (LOT-033 spec, difference 5) and the captures are listed below.
@Suite("Topic page flag against the legacy oracle (#306, #268)")
struct TopicPageFlagOracleTests {
    /// The bar link is the first `delflag` href of the page: legacy and #306 read the same link.
    static let overlap = ["P03m", "R21", "R32b", "R33b", "R61d", "R61e", "R63a", "R63e"]
    /// No `delflag` href anywhere and no `nonlu` href (anonymous pages, a deleted conversation): legacy `""`, #306 nil.
    static let noLink = ["R20", "R22a", "R22b", "R23", "R24", "R26", "R27", "R27b", "R28", "R31", "R32a", "RA5"]
    /// Intentional difference (LOT-033 difference 5): private conversations have no flag, legacy's `isFavoritesOrRead` falls back
    /// to the `nonlu` (mark unread) link there. #306 gives nil; the unread link is `TopicPageMetadata`'s, compared with
    /// the oracle's `unreadable` by `TopicPageMetadataOracleTests`.
    static let unreadLinkOnly = ["RA1", "RA2", "RA3", "RA4", "RU1", "RU2"]

    /// The folder of each case: `LOT-003-flag` holds the logged-in captures with the link that `LOT-003` lacked.
    private static let folders = ["R33b": "LOT-003-flag", "R61d": "LOT-003-flag", "R61e": "LOT-003-flag",
                                  "R63a": "LOT-003-flag", "R63e": "LOT-003-flag"]

    private struct Oracle: Decodable {
        struct Input: Decodable { var currentURL: String; var file: String }
        struct FastAnswer: Decodable { var isFavoritesOrRead: String; var isRedFlagged: Bool; var isUnreadable: Bool }
        struct Result: Decodable { var fastAnswer: FastAnswer }
        var exception: String?
        var input: Input
        var result: Result
    }

    private func load(_ caseID: String) throws -> (oracle: Oracle, html: String) {
        let folder = "Fixtures/" + (Self.folders[caseID] ?? "LOT-003")
        let json = try Fixture.text("\(caseID).oracle", extension: "json", subdirectory: folder)
        let oracle = try JSONDecoder().decode(Oracle.self, from: Data(json.utf8))
        // `input.file` is `../captures/<name>.html`, relative to the oracle folder.
        let name = try #require(oracle.input.file.split(separator: "/").last).dropLast(".html".count)
        return (oracle, try Fixture.capture(String(name)))
    }

    /// Every `href` value of the page containing `needle`, in document order, entities `&amp;` decoded (independent of both parsers).
    private func hrefs(containing needle: String, in html: String) -> [String] {
        html.matches(of: #/href="([^"]*)"/#).map { String($0.output.1).replacing("&amp;", with: "&") }.filter { $0.contains(needle) }
    }

    @Test("Overlap: the removal URL is legacy's isFavoritesOrRead and the red flag is legacy's isRedFlagged", arguments: overlap)
    func sameLinkSameFlag(caseID: String) throws {
        let (oracle, html) = try load(caseID)
        #expect(oracle.exception == nil)
        let legacy = oracle.result.fastAnswer
        // The precondition of the overlap, checked on the raw page: legacy's link is the first delflag href of the page.
        #expect(hrefs(containing: "delflag", in: html).first == legacy.isFavoritesOrRead)
        #expect(!legacy.isUnreadable)

        let found = try #require(try TopicPageMetadataParser.parse(html: html, pageURL: oracle.input.currentURL).flag)
        let expected = try #require(URL(string: legacy.isFavoritesOrRead, relativeTo: URL(string: "https://forum.hardware.fr")))
        #expect(found.removalURL.absoluteString == expected.absoluteString)
        #expect((found.flag == .red) == legacy.isRedFlagged)
    }

    @Test("No delflag or nonlu link: legacy has none, #306 gives no flag", arguments: noLink)
    func noLinkNoFlag(caseID: String) throws {
        let (oracle, html) = try load(caseID)
        #expect(oracle.result.fastAnswer.isFavoritesOrRead.isEmpty)
        #expect(!oracle.result.fastAnswer.isRedFlagged)
        #expect(try TopicPageMetadataParser.parse(html: html, pageURL: oracle.input.currentURL).flag == nil)
    }

    @Test("Intentional difference: on a private conversation legacy keeps the nonlu link, #306 gives no flag", arguments: unreadLinkOnly)
    func unreadLinkIsNotAFlag(caseID: String) throws {
        let (oracle, html) = try load(caseID)
        let legacy = oracle.result.fastAnswer
        #expect(legacy.isFavoritesOrRead.contains("/user/nonlu.php?"))
        #expect(legacy.isUnreadable && !legacy.isRedFlagged)
        #expect(hrefs(containing: "delflag", in: html).isEmpty)
        #expect(try TopicPageMetadataParser.parse(html: html, pageURL: oracle.input.currentURL).flag == nil)
    }

    @Test("Every topic oracle of LOT-003 and LOT-003-flag is in exactly one list")
    func listsCoverTheOracles() throws {
        let lists = Self.overlap + Self.noLink + Self.unreadLinkOnly
        #expect(Set(lists).count == lists.count)
        var mapped: Set<String> = []
        for folder in ["LOT-003", "LOT-003-flag"] {
            let json = try Fixture.text("oracle-map", extension: "json", subdirectory: "Fixtures/\(folder)")
            let map = try #require(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
            mapped.formUnion(map.keys.map { $0.replacing(".html", with: "") })
        }
        #expect(Set(lists) == mapped)
    }
}
