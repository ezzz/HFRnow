import Foundation
import HFRModels
import HFRNetwork
import HFRParsing
import Testing
@testable import HFRClient

/// The REST JSON against the HTML side: `R57a` against the home page `R01`, `R57b` against the list `R04`, captured six
/// minutes earlier (LOT-057). No legacy code read the REST API, so the HTML pages are the oracle.
@Suite("REST documents (LOT-057)")
struct RESTDocumentTests {
    @Test("R57a: the home page's 20 categories, in its order, with its titles and paths")
    func categoriesMatchTheHomePage() throws {
        let rest = try RESTDocument.categories(from: RESTCapture.data(RESTCapture.categories))
        let home = try ForumListParser.parse(Capture.page("R01-home-anon")).forums

        #expect(rest.count == 20)
        #expect(rest.map(\.title) == home.map(\.title))
        #expect(rest.map(\.path) == home.map(\.path))
        #expect(rest.map(\.categoryID) == home.map { ForumCatalogue.categoryID(forPath: $0.path) })
        let withSubforums = rest.filter { !$0.subforums.isEmpty }
        #expect(withSubforums.isEmpty)
        // The legacy oracle of the same page names the same forums, entities decoded (`&amp;` in the JSON), except
        // Apple, which legacy hid (HFR-PROTOCOL §6b, R01).
        let legacy = try Self.legacyHomeTitles()
        #expect(rest.map(\.title).filter { $0 != "Apple" } == legacy)
        #expect(rest.contains { $0.title == "Overclocking, Cooling & Modding" })
    }

    @Test("R57b: rows unchanged between the captures equal R04's: replies, pages, sticky, closed, last post date")
    func lastTopicsMatchTheHTMLList() throws {
        let rest = try RESTDocument.lastTopics(from: RESTCapture.data(RESTCapture.lastTopics), category: 13)
        let html = try TopicListParser.parse(
            Capture.page("R04-list-cat13-p1-anon"), pageURL: "https://forum.hardware.fr/hfr/Discussions/liste_sujet-1.htm"
        )
        #expect(rest.topics.count == 30)
        let sticky = rest.topics.map { $0.isSticky }
        #expect(sticky == Array(repeating: true, count: 5) + Array(repeating: false, count: 25))
        #expect(rest.categoryID == .forum(13))
        #expect(rest.navigation == PageNavigation(current: 1, last: 1))

        var compared = 0
        for row in rest.topics {
            let match = html.topics.first { $0.topicID == row.topicID }
            let other = try #require(match)
            // A post between the two reads changes the counts; R04 is the earlier capture.
            guard row.lastPost?.date == other.lastPost?.date else { continue }
            compared += 1
            #expect(row.repliesCount == other.repliesCount)
            #expect(row.pageCount == other.pageCount)
            #expect(row.isSticky == other.isSticky)
            #expect(row.isClosed == other.isClosed)
            // Pseudos in titles are anonymised with one map per file; the HTML parser trims the title.
            if !Self.holdsPseudo(row.title), !Self.holdsPseudo(other.title) {
                #expect(row.title.trimmingCharacters(in: .whitespaces) == other.title)
            }
        }
        #expect(compared == 28)
    }

    @Test("R57b: paths are the forum2.php pages the network layer requests")
    func pathsAreRequestPaths() throws {
        let rest = try RESTDocument.lastTopics(from: RESTCapture.data(RESTCapture.lastTopics), category: 13)
        let pizza = try #require(rest.topics.first { $0.topicID?.topic == 28563 })
        #expect(pizza.path == "/forum2.php?config=hfr.inc&cat=13&post=28563&page=1")
        #expect(pizza.pageCount == 2201)
        #expect(pizza.repliesCount == 88008)
        #expect(pizza.lastPagePath == "/forum2.php?config=hfr.inc&cat=13&post=28563&page=2201")
        #expect(pizza.lastPost?.path == pizza.lastPagePath)
        #expect(pizza.lastPost?.date == Date(timeIntervalSince1970: 1_792_979_400)) // 2026-10-26 02:50 Paris = 01:50Z
        #expect(pizza.readState == .unknown)
        #expect(pizza.flag == nil)
        #expect(!pizza.isPoll)
    }

    @Test("R57c: the topic equals R57b's row of the same topic; its sticky flag, which contradicts the lists, is not read")
    func topicMatchesItsRow() throws {
        let id = TopicID(category: .forum(13), topic: 28563)
        let topic = try RESTDocument.topic(from: RESTCapture.data(RESTCapture.topic), expected: id)
        let rows = try RESTDocument.lastTopics(from: RESTCapture.data(RESTCapture.lastTopics), category: 13).topics
        var row = try #require(rows.first { $0.topicID == id })
        #expect(!row.isSticky)
        let resource = try #require(RESTCapture.object(RESTCapture.topic)["resource"] as? [String: Any])
        #expect(resource["is_sticky"] as? Bool == true)
        // Pseudos are anonymised with one map per file.
        row.starterOrInterlocutors = topic.starterOrInterlocutors
        row.lastPost?.author = topic.lastPost?.author ?? ""
        #expect(topic == row)
        #expect(throws: ParsingError.invalidValue(field: "resource.id")) {
            try RESTDocument.topic(from: RESTCapture.data(RESTCapture.topic), expected: TopicID(category: .forum(13), topic: 28564))
        }
    }

    @Test("A topic list of another category is refused")
    func otherCategoryRefused() throws {
        #expect(throws: ParsingError.invalidValue(field: "resources.links.category")) {
            try RESTDocument.lastTopics(from: RESTCapture.data(RESTCapture.lastTopics), category: 14)
        }
    }

    @Test("Not JSON, the wrong resource, a missing field: typed errors naming the field only")
    func malformedAnswers() throws {
        #expect(throws: ParsingError.malformedDocument) { try RESTDocument.categories(from: Data("<html>".utf8)) }
        #expect(throws: ParsingError.malformedDocument) { try RESTDocument.categories(from: Data()) }
        // The topic list is not a category list, and the reverse.
        #expect(throws: ParsingError.invalidValue(field: "resource.resources.name")) {
            try RESTDocument.categories(from: RESTCapture.data(RESTCapture.lastTopics))
        }
        #expect(throws: ParsingError.invalidValue(field: "resource.resources.title")) {
            try RESTDocument.lastTopics(from: RESTCapture.data(RESTCapture.categories), category: 13)
        }
        // R57a without its first category's name.
        var object = try RESTCapture.object(RESTCapture.categories)
        var resource = try #require(object["resource"] as? [String: Any])
        var rows = try #require(resource["resources"] as? [[String: Any]])
        rows[0]["name"] = nil
        resource["resources"] = rows
        object["resource"] = resource
        let edited = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: ParsingError.invalidValue(field: "resource.resources.name")) { try RESTDocument.categories(from: edited) }
    }

    @Test("A category the catalogue does not know fails the decode, so the home page is read instead")
    func unknownCategoryFails() throws {
        var object = try RESTCapture.object(RESTCapture.categories)
        var resource = try #require(object["resource"] as? [String: Any])
        var rows = try #require(resource["resources"] as? [[String: Any]])
        // Category 7 is in no catalogue row (`ForumCatalogue`); its href follows the id, as HFR's do.
        rows[0]["id"] = 7
        rows[0]["href"] = "https://forum.hardware.fr/api/forums/hardwarefr/categories/7/"
        resource["resources"] = rows
        object["resource"] = resource
        let edited = try JSONSerialization.data(withJSONObject: object)
        #expect(throws: ParsingError.invalidValue(field: "resources.id")) { try RESTDocument.categories(from: edited) }
    }

    // MARK: - Helpers

    private static func holdsPseudo(_ title: String) -> Bool {
        title.contains(/user[0-9]+/)
    }

    /// The forum titles of the LOT-002 legacy oracle of `R01`.
    private static func legacyHomeTitles() throws -> [String] {
        let url = Capture.directory.deletingLastPathComponent().appendingPathComponent("LOT-002/R01.oracle.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        let forums = try #require(object?["result"] as? [[String: Any]])
        return forums.compactMap { $0["aTitle"] as? String }
    }
}
