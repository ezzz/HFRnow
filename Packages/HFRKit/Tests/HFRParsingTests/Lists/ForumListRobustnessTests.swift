import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// Failure, skipped-row and hostile-link behaviour of the home page parser (synthetic and in-memory mutations of captures).
@Suite("Forum list parser robustness")
struct ForumListRobustnessTests {
    // MARK: - Failures (synthetic snippets, not captures: these states were not captured)

    @Test("A body starting with a paragraph is a maintenance page carrying its message")
    func maintenance() {
        #expect(throws: ListPageFailure.maintenance("Maintenance en cours")) {
            try ForumListParser.parse("<html><body>\n<p> Maintenance en cours </p></body></html>")
        }
    }

    @Test("Pages without any forum row are malformed, whatever else they hold", arguments: [
        "", "<html><body id=\"x\"><table><tr class=\"main\"><td>a</td></tr></table></body></html>"
    ])
    func noRows(html: String) {
        #expect(throws: ListPageFailure.malformed("no forum row (tr class*=cat)")) { try ForumListParser.parse(html) }
    }

    @Test("A topic list capture is not a home page", arguments: ["R04-list-cat13-p1-anon", "R12-favourites-anon"])
    func otherPage(capture: String) throws {
        let html = try Fixture.capture(capture)
        #expect(throws: ListPageFailure.self) { try ForumListParser.parse(html) }
    }

    @Test("An unreadable row is skipped and counted, not fatal", arguments: [
        "<tr class=\"cat\"></tr>",
        "<tr class=\"cat\"><td>x</td></tr>",
        "<tr class=\"cat\"><td></td><td><a class=\"cCatTopic\" href=\"/hfr/a/liste_sujet-1.htm\">A</a></td></tr>",
        "<tr class=\"cat\"><td></td><td><b>A</b></td></tr>",
        "<tr class=\"cat\"><td></td><td><b><a class=\"cCatTopic\">A</a></b></td></tr>",
        "<tr class=\"cat\"><td></td><td><b><a class=\"cCatTopic\" href=\"\">A</a></b></td></tr>",
        "<tr class=\"cat\"><td></td><td><b> &nbsp; </b><a class=\"cCatTopic\" href=\"/hfr/a/liste_sujet-1.htm\">A</a></td></tr>"
    ])
    func unreadableRowSkipped(row: String) throws {
        let good = ForumListParserTests.row(id: "cat13", title: "Discussions", path: "/hfr/Discussions/liste_sujet-1.htm", subforums: [])
        let page = try ForumListParser.parse(ForumListParserTests.page(rows: row + good))
        #expect(page.forums.map(\.title) == ["Discussions"])
        let alone = ForumListParserTests.page(rows: row)
        #expect(throws: ListPageFailure.malformed("1 forum rows, none readable")) { try ForumListParser.parse(alone) }
    }

    @Test("R01 with an extra empty tr.cat still yields the 20 real forums")
    func capturePlusJunkRow() throws {
        let html = try Fixture.capture("R01-home-anon")
        let marker = try #require(html.range(of: "<tr class=\"cat "))
        let mutated = html.replacingCharacters(in: marker, with: "<tr class=\"cat\"></tr><tr class=\"cat ")
        #expect(try ForumListParser.parse(mutated) == ForumListParser.parse(html))
    }

    @Test("R01 with every cCatTopic renamed: rows exist but none is readable")
    func captureWithoutLinks() throws {
        let html = try Fixture.capture("R01-home-anon").replacing("cCatTopic", with: "cCatRenamed")
        #expect(throws: ListPageFailure.malformed("20 forum rows, none readable")) { try ForumListParser.parse(html) }
    }

    static let hostileLinks = [
        "//evil.example/x", "https://evil.example/hfr/x/liste_sujet-1.htm", "https://forum.hardware.fr//evil.example/x",
        "http://forum.hardware.fr:80/hfr/x/liste_sujet-1.htm", "javascript:alert(1)", "/\\evil.example/x"
    ]

    @Test("R01 with a hostile category link: the row is skipped", arguments: hostileLinks)
    func hostileCategoryLink(link: String) throws {
        let html = try Fixture.capture("R01-home-anon")
        let target = "href=\"/hfr/Discussions/liste_sujet-1.htm\" class=\"cCatTopic\""
        #expect(html.contains(target))
        let page = try ForumListParser.parse(html.replacing(target, with: "href=\"\(link)\" class=\"cCatTopic\""))
        #expect(page.forums.count == 19)
        #expect(page.forums.allSatisfy { $0.title != "Discussions" && !$0.path.contains("evil") })
    }

    @Test("R01 with a hostile sub-forum link: the link is dropped", arguments: hostileLinks)
    func hostileSubforumLink(link: String) throws {
        let html = try Fixture.capture("R01-home-anon")
        let target = "href=\"/hfr/Discussions/Actualite/liste_sujet-1.htm\" class=\"Tableau\""
        #expect(html.contains(target))
        let page = try ForumListParser.parse(html.replacing(target, with: "href=\"\(link)\" class=\"Tableau\""))
        let forum = try #require(page.forums.first { $0.categoryID == .forum(13) })
        #expect(forum.subforums.count == 14)
        #expect(!forum.subforums.contains { $0.title == "Actualité" })
        #expect(page.forums.flatMap(\.subforums).allSatisfy { !$0.path.contains("evil") && $0.path.hasPrefix("/") })
    }

    @Test("Absolute https links to the forum are reduced to their path")
    func absoluteForumLink() throws {
        let row = "<tr class=\"cat\" id=\"cat13\"><td></td><td><b><a class=\"cCatTopic\" "
            + "href=\"https://forum.hardware.fr/hfr/Discussions/liste_sujet-1.htm\">D</a></b></td></tr>"
        #expect(try ForumListParser.parse(ForumListParserTests.page(rows: row)).forums.first?.path == "/hfr/Discussions/liste_sujet-1.htm")
    }

    @Test("Only the cat query parameter makes the private message row; cat=prive inside another value does not")
    func privateMessageDetectionIsExact() throws {
        let row = ForumListParserTests.row(
            id: "cat13", title: "Discussions", path: "/hfr/Discussions/liste_sujet-1.htm?return=cat=prive", subforums: []
        )
        let page = try ForumListParser.parse(ForumListParserTests.page(rows: row))
        #expect(page.forums.map(\.title) == ["Discussions"])
        #expect(page.unreadPrivateMessages == nil)
    }

    @Test("A sub-forum listed twice by the page appears once, at its first position")
    func repeatedSubforum() throws {
        let row = ForumListParserTests.row(
            id: "cat13", title: "Discussions", path: "/hfr/Discussions/liste_sujet-1.htm",
            subforums: [("A", "/hfr/Discussions/a/liste_sujet-1.htm"), ("B", "/hfr/Discussions/b/liste_sujet-1.htm"),
                        ("A bis", "/hfr/Discussions/a/liste_sujet-1.htm")]
        )
        #expect(try ForumListParser.parse(ForumListParserTests.page(rows: row)).forums.first?.subforums.map(\.title) == ["A", "B"])
    }

    @Test("A sub-forum link without href is dropped")
    func subforumWithoutHref() throws {
        let row = "<tr class=\"cat\" id=\"cat13\"><td></td><td><b>"
            + "<a class=\"cCatTopic\" href=\"/hfr/Discussions/liste_sujet-1.htm\">D</a></b>"
            + "<a class=\"Tableau\">x</a><a class=\"Tableau\" href=\"/hfr/Discussions/y/liste_sujet-1.htm\">y</a></td></tr>"
        #expect(try ForumListParser.parse(ForumListParserTests.page(rows: row)).forums.first?.subforums.map(\.title) == ["y"])
    }

    @Test("An empty hash_check is logged out; a row id that is not cat<N> falls back to the catalogue")
    func syntheticSessionAndIDs() throws {
        let row = ForumListParserTests.row(id: "weird", title: "Discussions", path: "/hfr/Discussions/liste_sujet-1.htm", subforums: [])
        let out = try ForumListParser.parse(ForumListParserTests.page(rows: row, hashCheck: ""))
        #expect(out.isLoggedIn == false && out.hashCheck == nil)
        #expect(out.forums.first?.categoryID == .forum(13))
        let unknown = ForumListParserTests.row(id: "weird", title: "Nouveau", path: "/hfr/Nouveau/liste_sujet-1.htm", subforums: [])
        #expect(try ForumListParser.parse(ForumListParserTests.page(rows: unknown, hashCheck: "abc")).forums.first?.categoryID == nil)
    }
}
