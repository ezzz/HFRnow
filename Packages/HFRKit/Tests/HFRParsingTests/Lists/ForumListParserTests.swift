import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// Home page parser: differential tests against the LOT-002 legacy oracle on the captured pages, then focused checks.
@Suite("Forum list parser")
struct ForumListParserTests {
    /// Capture file and oracle case of each home page in the corpus (`oracle-map.json` entries of kind `forums`).
    static let captures: [(oracle: String, capture: String)] = [
        ("R01", "R01-home-anon"),
        ("R02", "R02-home-logged-in-unread-mp"),
        ("R03", "R03-home-logged-in-no-unread-mp")
    ]

    // MARK: - Differential tests (ADR 0004)

    @Test("Full result equals the legacy oracle, minus the listed deviations", arguments: captures)
    func matchesOracle(oracleName: String, captureName: String) throws {
        let oracle = try ForumListOracle.load(oracleName)
        let html = try Fixture.capture(captureName)
        #expect(oracle.kind == "forums")
        #expect(oracle.exception == nil)
        #expect(oracle.input.file == "../captures/\(captureName).html")
        #expect(oracle.input.bytes == html.utf8.count)

        let page = try ForumListParser.parse(html)

        // Session facts: legacy "logged in" is exactly "hash_check has a value"; the badge write is the unread count.
        #expect(page.hashCheck == oracle.sideEffects.hashCheck)
        #expect(page.isLoggedIn == (oracle.sideEffects.hashCheck != nil))
        #expect(page.unreadPrivateMessages == oracle.sideEffects.nbMP)

        // Deviation 1: all categories are returned; legacy dropped "Apple" when logged out. Undo that to compare.
        let comparable = page.forums.filter { page.isLoggedIn || $0.title != "Apple" }
        let expected = try oracle.result.unwrap().map(Self.category(from:))
        #expect(comparable == expected)
        #expect(page.forums.count == expected.count + (page.isLoggedIn ? 0 : 1))
    }

    /// Legacy forum as the new model. Deviation 2: no "all" copy of the parent in `subforums`. Deviation 3: `categoryID`
    /// is known (legacy `aID` was never set), taken here from the catalogue, which the parser reads from the row id.
    private static func category(from forum: ForumListOracle.Forum) throws -> ForumCategory {
        #expect(forum.aID.isEmpty)
        let subCats = forum.subCats ?? []
        if let parent = subCats.first {
            #expect(parent.aTitle == forum.aTitle)
            #expect(parent.aURL == forum.aURL)
            #expect(parent.subCats?.isEmpty ?? true)
        }
        return ForumCategory(
            categoryID: ForumCatalogue.categoryID(forPath: forum.aURL),
            title: forum.aTitle,
            path: forum.aURL,
            subforums: subCats.dropFirst().map { ForumLink(title: $0.aTitle, path: $0.aURL) }
        )
    }

    @Test("oracle-map.json declares the three home pages as kind forums")
    func oracleMap() throws {
        let map = try Fixture.text("oracle-map", extension: "json", subdirectory: "Fixtures/LOT-002")
        let entries = try #require(JSONSerialization.jsonObject(with: Data(map.utf8)) as? [String: [String: Any]])
        for (oracle, capture) in Self.captures {
            let entry = try #require(entries["\(oracle).html"])
            #expect(entry["kind"] as? String == "forums")
            #expect(entry["path"] as? String == "../captures/\(capture).html")
        }
    }

    // MARK: - Captured pages

    @Test("R01 logged out: 20 categories with Apple, no token, no private message row")
    func loggedOut() throws {
        let page = try ForumListParser.parse(Fixture.capture("R01-home-anon"))
        #expect(page.forums.count == 20)
        #expect(page.isLoggedIn == false)
        #expect(page.hashCheck == nil)
        #expect(page.unreadPrivateMessages == nil)
        let apple = try #require(page.forums.first { $0.title == "Apple" })
        #expect(apple.path == "/hfr/apple/liste_sujet-1.htm")
        #expect(apple.categoryID == .forum(25))
        #expect(apple.subforums.count == 7)
    }

    @Test("R02 and R03 logged in: token kept, unread count 10 then 0 when the row shows no number")
    func loggedIn() throws {
        let unread = try ForumListParser.parse(Fixture.capture("R02-home-logged-in-unread-mp"))
        #expect(unread.isLoggedIn)
        #expect(unread.hashCheck == "REDACTED")
        #expect(unread.unreadPrivateMessages == 10)
        let none = try ForumListParser.parse(Fixture.capture("R03-home-logged-in-no-unread-mp"))
        #expect(none.isLoggedIn)
        #expect(none.unreadPrivateMessages == 0)
        #expect(unread.forums == none.forums)
    }

    @Test("The private message row is not a category", arguments: ["R02-home-logged-in-unread-mp", "R03-home-logged-in-no-unread-mp"])
    func privateRowExcluded(capture: String) throws {
        let page = try ForumListParser.parse(Fixture.capture(capture))
        #expect(page.forums.allSatisfy { !$0.path.contains("cat=prive") && $0.categoryID != .privateMessages })
    }

    @Test("Achats & Ventes: the home link to its Hardware sub-forum is corrected to the category list")
    func achatsVentesRewrite() throws {
        let html = try Fixture.capture("R01-home-anon")
        #expect(html.contains("href=\"/hfr/AchatsVentes/Hardware/liste_sujet-1.htm\" class=\"cCatTopic\""))
        let forum = try #require(try ForumListParser.parse(html).forums.first { $0.title == "Achats & Ventes" })
        #expect(forum.path == "/hfr/AchatsVentes/liste_sujet-1.htm")
        #expect(forum.categoryID == .forum(6))
        // The sub-forum "Hardware" of the same category keeps its own path.
        #expect(forum.subforums.contains(ForumLink(title: "Hardware", path: "/hfr/AchatsVentes/Hardware/liste_sujet-1.htm")))
    }

    @Test("Titles are decoded and trimmed; a category without sub-forum has an empty list")
    func titlesAndEmptySubforums() throws {
        let forums = try ForumListParser.parse(Fixture.capture("R01-home-anon")).forums
        #expect(forums.contains { $0.title == "Overclocking, Cooling & Modding" })
        let intelligence = try #require(forums.first { $0.categoryID == .forum(32) })
        #expect(intelligence.title == "Intelligence Artificielle")
        #expect(intelligence.subforums.isEmpty)
        #expect(forums.allSatisfy { $0.title == $0.title.trimmingCharacters(in: .whitespacesAndNewlines) && !$0.title.isEmpty })
    }

    // MARK: - Category ids (audit B open question 2)

    @Test("Row ids give the cat id of every category and agree with the catalogue")
    func rowIDsAgreeWithCatalogue() throws {
        for forum in try ForumListParser.parse(Fixture.capture("R01-home-anon")).forums {
            #expect(forum.categoryID != nil)
            #expect(forum.categoryID == ForumCatalogue.categoryID(forPath: forum.path), "\(forum.title)")
        }
    }

    @Test("R07 category selector: the same 20 (id, title) pairs as the home page rows, in the same order")
    func agreesWithListPageSelector() throws {
        let list = try Fixture.capture("R07-list-graphisme-anon")
        let start = try #require(list.range(of: "<select name=\"cat\""))
        let end = try #require(list.range(of: "</select>", range: start.upperBound..<list.endIndex))
        let options = list[start.lowerBound..<end.lowerBound].matches(of: /<option value="([0-9]+)"[^>]*>([^<]*)<\/option>/).map {
            (id: CategoryID.forum(Int($0.output.1) ?? -1), title: String($0.output.2).replacing("&amp;", with: "&"))
        }
        let forums = try ForumListParser.parse(Fixture.capture("R01-home-anon")).forums
        #expect(options.count == 20)
        #expect(options.map(\.id) == forums.map(\.categoryID))
        #expect(options.map(\.title) == forums.map(\.title))
    }

    @Test("The catalogue keeps two forums the live home page no longer lists (9 and 24)")
    func catalogueSuperset() throws {
        let live = Set(try ForumListParser.parse(Fixture.capture("R01-home-anon")).forums.compactMap(\.categoryID))
        let catalogue = Set(ForumCatalogue.entries.map(\.categoryID))
        #expect(live.isSubset(of: catalogue))
        #expect(catalogue.subtracting(live) == [.forum(9), .forum(24)])
    }

    // MARK: - Sub-forum injection

    @Test("R02 Programmation: injected sub-forums follow their listed trigger, as legacy")
    func injectionOrder() throws {
        let html = try Fixture.capture("R02-home-logged-in-unread-mp")
        let forum = try #require(try ForumListParser.parse(html).forums.first { $0.categoryID == .forum(10) })
        #expect(forum.subforums.map(\.title) == [
            "C++", "C#/.NET managed", "HTML/CSS", "Java", "Langages fonctionnels", "PDA", "Perl", "PHP", "Python", "Ruby/Rails",
            "SQL/NoSQL", "Shell/Batch", "VB/VBA/VBS", "XML/XSL"
        ])
        // Only 6 of those 14 are links of the page: the others come from the table.
        #expect(forum.subforums.filter { html.contains("href=\"\($0.path)\" class=\"Tableau\"") }.count == 6)
    }

    @Test("Injection places sub-forums before the trigger when the table says so (API-Win32 is not on the live page)")
    func injectionBefore() throws {
        let html = Self.page(rows: Self.row(
            id: "cat10", title: "Programmation", path: "/hfr/Programmation/liste_sujet-1.htm",
            subforums: [("API", "/hfr/Programmation/API-Win32/liste_sujet-1.htm")]
        ))
        let forum = try #require(try ForumListParser.parse(html).forums.first)
        #expect(forum.subforums.map(\.title) == ["Divers", "ADA", "Algo", "API", "ASM", "ASP", "Biblio Links", "C"])
    }

    @Test("Injections are not duplicated when the page lists the sub-forum itself")
    func injectionDedupe() throws {
        let html = Self.page(rows: Self.row(
            id: "cat1", title: "Hardware", path: "/hfr/Hardware/liste_sujet-1.htm",
            subforums: [("Mini PC", "/hfr/Hardware/minipc/liste_sujet-1.htm"), ("Bench", "/hfr/Hardware/Benchs/liste_sujet-1.htm")]
        ))
        let forum = try #require(try ForumListParser.parse(html).forums.first)
        #expect(forum.subforums.map(\.title) == ["Mini PC", "Bench"])
        let without = Self.page(rows: Self.row(
            id: "cat1", title: "Hardware", path: "/hfr/Hardware/liste_sujet-1.htm",
            subforums: [("Mini PC", "/hfr/Hardware/minipc/liste_sujet-1.htm")]
        ))
        #expect(try ForumListParser.parse(without).forums.first?.subforums.map(\.title) == ["Mini PC", "Bench"])
    }

    @Test("Every injected path is unique and a topic list path")
    func injectionTableShape() {
        let paths = SubforumInjection.all.flatMap { $0.before + $0.after }.map(\.path)
        #expect(Set(paths).count == paths.count)
        #expect(paths.allSatisfy { $0.hasPrefix("/hfr/") && $0.hasSuffix("/liste_sujet-1.htm") })
        #expect(Set(SubforumInjection.all.map(\.trigger)).count == SubforumInjection.all.count)
    }

    // MARK: - Helpers

    /// Minimal home page around some rows. Hand-written for the failure and edge tests only.
    static func page(rows: String, hashCheck: String? = nil) -> String {
        let field = hashCheck.map { "<input type=\"hidden\" name=\"hash_check\" value=\"\($0)\" />" } ?? ""
        return "<html><body id=\"unique__home__listing_category\">\(field)<table>\(rows)</table></body></html>"
    }

    /// A forum row shaped like the captured ones.
    static func row(id: String, title: String, path: String, subforums: [(String, String)]) -> String {
        let links = subforums.map { "<a href=\"\($0.1)\" class=\"Tableau\">\($0.0)</a>" }.joined(separator: " | ")
        return "<tr class=\"cat cBackCouleurTab1\" id=\"\(id)\"><td class=\"catCase0\"></td><td class=\"catCase1\">"
            + "<b><a href=\"\(path)\" class=\"cCatTopic\"> \(title)</a></b><br />\(links)</td></tr>"
    }
}

private extension Optional {
    /// The wrapped value, or a failed expectation when nil.
    func unwrap() throws -> Wrapped {
        try #require(self)
    }
}
