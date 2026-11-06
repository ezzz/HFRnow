import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// LOT-028: AQ RSS feed (`T01`, differential against the legacy oracle) and per-topic listing (`T02`, no legacy parser).
@Suite("AQ parsers")
struct AQParsersTests {
    // MARK: - Fixtures

    static func feedXML() throws -> String { try Fixture.capture("T01-aq-rss-feed", extension: "xml") }
    static func alertsXML() throws -> String { try Fixture.capture("T02-aq-alerts-by-topic", extension: "xml") }

    private struct LegacyItem {
        let aqTitle: String, comment: String, initiator: String, topicTitle: String, link: String, isNew: Bool
    }

    /// The legacy `AQRSSParserDelegate` output on `T01` (`Fixtures/LOT-028/T01.oracle.json`), with its inputs.
    private struct Oracle {
        let items: [LegacyItem]
        let newCount: Int
        let filterCategory25: Bool
        let lastCheck: Date

        static func load() throws -> Oracle {
            let text = try Fixture.text("T01.oracle", extension: "json", subdirectory: "Fixtures/LOT-028")
            let root = try #require(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any])
            #expect(root["kind"] as? String == "aq-rss")
            let result = try #require(root["result"] as? [String: Any])
            let context = try #require((root["input"] as? [String: Any])?["context"] as? [String: Any])
            let rows = try #require(result["items"] as? [[String: Any]])
            let items = try rows.map { row in
                LegacyItem(
                    aqTitle: try #require(row["aqTitle"] as? String), comment: try #require(row["comment"] as? String),
                    initiator: try #require(row["initiator"] as? String), topicTitle: try #require(row["topicTitle"] as? String),
                    link: try #require(row["link"] as? String), isNew: try #require(row["isNew"] as? Bool)
                )
            }
            let lastCheck = try #require(context["lastCheck"] as? String)
            return Oracle(
                items: items, newCount: try #require(result["newCount"] as? Int),
                filterCategory25: try #require(context["filterCategory25"] as? Bool),
                lastCheck: try Date(lastCheck, strategy: .iso8601)
            )
        }
    }

    // MARK: - RSS feed against the oracle

    @Test("feed: every field equals the legacy item, topic titles entity-decoded (B4)")
    func feedEqualsOracle() throws {
        let oracle = try Oracle.load()
        let items = try AQFeedParser.parse(Self.feedXML())
        // The oracle ran with the category-25 filter on; the parser keeps every item, the caller filters.
        let visible = items.filter { AQFeedParser.category(of: $0) != 25 }
        #expect(oracle.filterCategory25)
        #expect(visible.count == oracle.items.count)
        #expect(items.count == 25)
        for (item, legacy) in zip(visible, oracle.items) {
            #expect(item.title == legacy.aqTitle)
            #expect(item.comment == legacy.comment)
            #expect(item.initiator == legacy.initiator)
            #expect(item.link.absoluteString == legacy.link)
            #expect(item.topicTitle == HFRText.decodingHTMLEntities(legacy.topicTitle))
        }
    }

    @Test("feed: the items legacy marked new are the ones published since the last check")
    func feedNewness() throws {
        let oracle = try Oracle.load()
        let items = try AQFeedParser.parse(Self.feedXML())
        let flags = try items.map { try #require($0.publishedAt) >= oracle.lastCheck }
        #expect(flags == oracle.items.map(\.isNew))
        #expect(flags.filter { $0 }.count == oracle.newCount)
        #expect(oracle.newCount == 2)
    }

    @Test("feed: pubDate is the instant the description prints as Paris wall-clock time")
    func feedDateMatchesDescription() throws {
        let xml = try Self.feedXML()
        let items = try AQFeedParser.parse(xml)
        let printed = xml.matches(of: /\[le ([0-9-]+ à [0-9:]+)\]/).compactMap { HFRDate.date(from: String($0.output.1)) }
        #expect(printed.count == items.count)
        #expect(items.map { $0.publishedAt } == printed.map { Optional($0) })
    }

    @Test("feed: the entities legacy left in four topic titles are decoded, none remain")
    func feedDecodesEntities() throws {
        let oracle = try Oracle.load()
        let items = try AQFeedParser.parse(Self.feedXML())
        let encoded = oracle.items.filter { $0.topicTitle.contains("&") }
        #expect(encoded.count == 4)
        for item in items {
            #expect(!item.topicTitle.contains("&quot;") && !item.topicTitle.contains("&#039;") && !item.topicTitle.contains("&amp;"))
        }
        #expect(items[0].topicTitle == "Topic Hontes - \"La vraie honte c'est...\" = sanction")
    }

    @Test("feed: the category of a link is its cat parameter")
    func feedCategory() throws {
        let items = try AQFeedParser.parse(Self.feedXML())
        // Canonical `/hfr/<cat>/<subcat>/…-sujet_<post>_<page>.htm` links carry no `cat` (2 of 25): legacy never hid them either.
        let canonical = items.filter { $0.link.path.hasSuffix(".htm") }
        #expect(canonical.count == 2)
        #expect(canonical.allSatisfy { AQFeedParser.category(of: $0) == nil })
        #expect(items.compactMap { AQFeedParser.category(of: $0) }.count == items.count - canonical.count)
        #expect(AQFeedParser.category(of: items[0]) == 13)
        // The capture holds no category-25 item: the same link with its category changed shows the filter's input.
        let apple = AQFeedItem(
            topicTitle: "", title: "", comment: "", initiator: "", publishedAt: nil,
            link: try #require(URL(string: items[0].link.absoluteString.replacing("cat=13", with: "cat=25")))
        )
        #expect(AQFeedParser.category(of: apple) == 25)
    }

    @Test("feed: items without a usable link are skipped, as legacy skipped an empty one")
    func feedSkipsLinklessItems() throws {
        let xml = try Self.feedXML()
        let first = try #require(xml.firstMatch(of: /<link>[^<]*<\/link>\s*<guid>/))
        let broken = xml.replacing(first.output, with: "<link></link><guid>", maxReplacements: 1)
        #expect(try AQFeedParser.parse(broken).count == 24)
        let hostile = xml.replacing(first.output, with: "<link>javascript:alert(1)</link><guid>", maxReplacements: 1)
        #expect(try AQFeedParser.parse(hostile).count == 24)
    }

    @Test("feed: a link to another host is skipped, the other items stay")
    func feedSkipsOffForumLinks() throws {
        let xml = try Self.feedXML()
        let first = try #require(xml.firstMatch(of: /<link>[^<]*<\/link>\s*<guid>/))
        let offSite = xml.replacing(first.output, with: "<link>https://example.invalid/x?cat=13</link><guid>", maxReplacements: 1)
        #expect(try AQFeedParser.parse(offSite).count == 24)
    }

    @Test("feed: captures are case-insensitive and the channel blurb is not an item description")
    func feedDescriptionReading() throws {
        let xml = try Self.feedXML()
        let shouted = xml.replacing("detectée", with: "DETECTÉE", maxReplacements: 1)
        #expect(try AQFeedParser.parse(shouted).first?.topicTitle == AQFeedParser.parse(xml).first?.topicTitle)
        let sentence = "Pour ne rien rater du meilleur d'HFR, en toutes circonstances"
        let blurb = xml.replacing("Une qualitaÿ a été", with: "\(sentence) Une qualitaÿ a été", maxReplacements: 1)
        let item = try #require(AQFeedParser.parse(blurb).first)
        #expect(item.topicTitle == AQFeedParser.missingTopicTitle)
    }

    @Test("feed: a description without the expected sentences gets the legacy placeholders")
    func feedPlaceholders() throws {
        let xml = try Self.feedXML()
        let description = try #require(xml.firstMatch(of: /<description><!\[CDATA\[(?:(?!\]\]>).)*\]\]><\/description>/))
        let stripped = xml.replacing(description.output, with: "<description>rien</description>", maxReplacements: 1)
        let item = try #require(AQFeedParser.parse(stripped).first)
        #expect(item.topicTitle == AQFeedParser.missingTopicTitle)
        #expect(item.initiator == AQFeedParser.missingInitiator)
        #expect(item.comment.isEmpty)
    }

    @Test("feed: something that is not an RSS feed is an error, not an empty list")
    func feedRejectsOtherDocuments() throws {
        #expect(throws: ParsingError.missingElement("rss > channel")) { try AQFeedParser.parse("") }
        #expect(throws: ParsingError.missingElement("rss > channel")) { try AQFeedParser.parse("<html><body>502</body></html>") }
        #expect(throws: ParsingError.missingElement("rss > channel")) { try AQFeedParser.parse(Self.alertsXML()) }
        let empty = #"<?xml version="1.0"?><rss version="2.0"><channel><title>t</title></channel></rss>"#
        #expect(try AQFeedParser.parse(empty).isEmpty)
    }

    @Test("pubDate: offsets, GMT, impossible dates and other shapes")
    func publicationDates() {
        #expect(RFC822Date.date(from: "Sun, 11 Oct 2026 10:31:57 +0200") == Date(timeIntervalSince1970: 1_791_707_517))
        #expect(RFC822Date.date(from: "Sun, 11 Oct 2026 08:31:57 GMT") == RFC822Date.date(from: "Sun, 11 Oct 2026 10:31:57 +0200"))
        #expect(RFC822Date.date(from: "Sun, 11 Oct 2026 08:31:57 -0130") == RFC822Date.date(from: "Sun, 11 Oct 2026 10:01:57 GMT"))
        #expect(RFC822Date.date(from: "Sun, 31 Feb 2026 10:31:57 +0200") == nil)
        #expect(RFC822Date.date(from: "Sun, 11 Oct 26 10:31:57 +0200") == nil)
        #expect(RFC822Date.date(from: "Sun, 11 Foo 2026 10:31:57 +0200") == nil)
        #expect(RFC822Date.date(from: "11-10-2026") == nil)
    }

    // MARK: - Per-topic listing

    @Test("listing: every alert of the capture, newest first, with its five attributes")
    func listing() throws {
        let alerts = try AQAlertListParser.parse(Self.alertsXML())
        #expect(alerts.count == 123)
        let first = alerts[0]
        #expect(first == AQAlert(id: 13642, title: "x x x x", initiator: "user3", dateText: "11-10-2026", postIDs: [75_396_914]))
        #expect(alerts.map(\.id) == alerts.map(\.id).sorted(by: >))
        #expect(Set(alerts.map(\.id)).count == alerts.count)
    }

    @Test("listing: attribute entities are decoded, spaces and repeated numbers kept as served")
    func listingAsServed() throws {
        let alerts = try AQAlertListParser.parse(Self.alertsXML())
        #expect(alerts.contains { $0.title == "\"x, x x x !\"" })
        #expect(alerts.contains { $0.title == "x x x & x" })
        #expect(alerts.contains { $0.title == "x " })
        #expect(alerts.allSatisfy { !$0.title.contains("&quot;") && !$0.title.contains("&amp;") })
        #expect(alerts.contains { $0.postIDs == [47_934_539, 47_934_539] })
        #expect(alerts.contains { $0.postIDs == [45_800_082, 45_810_920] })
    }

    @Test("listing: the reported-message question legacy asked with contains(postID)")
    func listingReported() throws {
        let alerts = try AQAlertListParser.parse(Self.alertsXML())
        #expect(AQAlertListParser.isReported(postID: 75_396_914, in: alerts))
        #expect(AQAlertListParser.isReported(postID: 45_810_920, in: alerts))
        // A substring of a reported number is not that message (legacy `contains` said yes).
        #expect(!AQAlertListParser.isReported(postID: 7_539_691, in: alerts))
        #expect(!AQAlertListParser.isReported(postID: 1, in: alerts))
    }

    @Test("listing: a malformed record is an error naming the field, never a skipped alert")
    func listingErrors() throws {
        let xml = try Self.alertsXML()
        #expect(throws: ParsingError.missingElement("alertes")) { try AQAlertListParser.parse("<html>502</html>") }
        #expect(throws: ParsingError.missingElement("alertes")) { try AQAlertListParser.parse(Self.feedXML()) }
        #expect(try AQAlertListParser.parse("<?xml version=\"1.0\"?><alertes></alertes>").isEmpty)
        #expect(throws: ParsingError.invalidValue(field: "id")) {
            try AQAlertListParser.parse(xml.replacing("alerte id=\"13642\"", with: "alerte id=\"abc\"", maxReplacements: 1))
        }
        #expect(throws: ParsingError.invalidValue(field: "postsIds")) {
            try AQAlertListParser.parse(xml.replacing("postsIds=\"75396914\"", with: "postsIds=\"75396914,\"", maxReplacements: 1))
        }
        #expect(throws: ParsingError.invalidValue(field: "postsIds")) {
            try AQAlertListParser.parse(xml.replacing("postsIds=\"75396914\"", with: "postsIds=\"0\"", maxReplacements: 1))
        }
        #expect(throws: ParsingError.missingElement("alertes")) {
            try AQAlertListParser.parse("<wrap>" + xml + "</wrap>")
        }
        #expect(throws: ParsingError.invalidValue(field: "date")) {
            try AQAlertListParser.parse(xml.replacing("date=\"11-10-2026\"", with: "date=\"2026-10-11\"", maxReplacements: 1))
        }
        #expect(throws: ParsingError.missingAttribute(element: "alerte", attribute: "pseudoInitiateur")) {
            try AQAlertListParser.parse(xml.replacing("pseudoInitiateur=\"user3\" ", with: "", maxReplacements: 1))
        }
    }
}
