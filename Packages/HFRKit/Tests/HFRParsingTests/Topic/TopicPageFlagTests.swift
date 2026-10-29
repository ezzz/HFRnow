import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// #306: the function bar's `delflag.php` link and its icon. Expectations are read from the raw captures: the LOT-003 oracle
/// does not export legacy's `isFavoritesOrRead` (LESSONS 52). Scope and origin rules use in-memory edits of captures.
@Suite("Topic page flag (#306)")
struct TopicPageFlagTests {
    private static let removal = "https://forum.hardware.fr/user/delflag.php?config=hfr.inc&"
    private static let pizza = "cat=13&subcat=433&post=28563&page=1&p=1&sondage=0&owntopic=0&new=0"
    private static let ownTopic = "cat=6&subcat=173&post=9900001&page=1&p=1&sondage=0&owntopic=0&new=0"
    private static let ownPost = "cat=13&subcat=430&post=6510&page=30&p=1&sondage=0&owntopic=0&new=0"
    /// The start of `R21`'s bar link, as served.
    private static let barLink = #"<a href="/user/delflag.php?config=hfr.inc&amp;cat=13&amp;subcat=433&amp;post=28563"#

    private func flag(_ capture: String) throws -> TopicPageFlag? {
        try flag(html: Fixture.capture(capture))
    }

    private func flag(html: String) throws -> TopicPageFlag? {
        try TopicPageMetadataParser.parse(html: html, pageURL: "/forum2.php?config=hfr.inc&cat=13&post=28563&page=1").flag
    }

    // MARK: - Captures

    @Test("Every logged-in capture with the link: its icon gives the flag, the link is kept as printed", arguments: [
        ("P03m-topic-p1-logged-in-favourite", TopicFlag.yellow, pizza),
        ("R63a-public-own-topic-first-page", .yellow, ownTopic),
        ("R63e-public-own-topic-after-restore", .yellow, ownTopic),
        ("R21-topic-p1-logged-in", .red, pizza),
        ("R32b-topic-poll-logged-in-not-voted", .red, "cat=13&subcat=431&post=98162&page=1&p=1&sondage=0&owntopic=0&new=0"),
        ("R33b-topic-poll-already-voted", .blue, "cat=25&subcat=525&post=8900&page=1&p=1&sondage=0&owntopic=1&new=0"),
        ("R61d-public-topic-last-page-own-post", .blue, ownPost),
        ("R61e-public-topic-after-delete", .blue, ownPost)
    ])
    func capturedFlag(capture: String, expected: TopicFlag, query: String) throws {
        let url = try #require(URL(string: Self.removal + query))
        #expect(try flag(capture) == TopicPageFlag(flag: expected, removalURL: url))
    }

    @Test("P03m's link is exactly the request P03n sent, which HFR confirmed with \"Drapeau effacé avec succès\"")
    func linkIsTheCapturedRemoval() throws {
        struct Meta: Decodable { let url: String }
        let meta = try JSONDecoder().decode(Meta.self, from: Data(Fixture.capture("P03n", extension: "meta.json").utf8))
        #expect(try flag("P03m-topic-p1-logged-in-favourite")?.removalURL.absoluteString == meta.url)
    }

    @Test("No link, no flag: anonymous pages and private conversations", arguments: [
        "R20-topic-p1-anon", "R22a-topic-middle-page-anon", "R24-topic-beyond-last-page-anon",
        "RA1-mp-thread-after-create", "RU2-mp-thread-recipient-after-owner-delete", "RA5-mp-thread-after-delete-owner"
    ])
    func noFlag(capture: String) throws {
        #expect(try flag(capture) == nil)
    }

    // MARK: - Rules (in-memory edits of captures)

    @Test("A delflag link posted in a message is never the topic's flag, with or without one in the bar")
    func messageLinkIsIgnored() throws {
        let posted = #"<a href="/user/delflag.php?config=hfr.inc&amp;cat=13&amp;post=28563&amp;owntopic=0">x</a>"#
        for capture in ["R20-topic-p1-anon", "R21-topic-p1-logged-in"] {
            var html = try Fixture.capture(capture)
            // R21 keeps its bar but loses the bar's link; R20 has none.
            html = html.replacing(Self.barLink, with: #"<a href="/user/email.php?config=hfr.inc&amp;cat=13&amp;subcat=433&amp;post=28563"#)
            let message = try #require(html.firstRange(of: #"<div id="para"#))
            html.insert(contentsOf: posted, at: message.lowerBound)
            #expect(try flag(html: html) == nil, "\(capture)")
        }
    }

    @Test("Only a table row carries the bar: another element with the bar's class before it is not the bar")
    func barIsATableRow() throws {
        var html = try Fixture.capture("R21-topic-p1-logged-in")
        let decoy = #"<div class="fondForum2Fonctions"><a href="/user/delflag.php?config=hfr.inc&amp;cat=13&amp;post=1&amp;owntopic=0">"#
            + #"<img src="/images/defaut/flagn1.gif"></a></div>"#
        let body = try #require(html.firstRange(of: "<body"))
        let open = try #require(html[body.lowerBound...].firstIndex(of: ">"))
        html.insert(contentsOf: decoy, at: html.index(after: open))
        let found = try #require(try flag(html: html))
        #expect(found.flag == .red)
        #expect(!found.removalURL.absoluteString.contains("post=1&"))
    }

    @Test("A bar link off the forum origin or to another path is refused", arguments: [
        "https://evil.example/user/delflag.php?", "http://forum.hardware.fr:80/user/delflag.php?",
        "https://forum.hardware.fr:8443/user/delflag.php?", "https://user@forum.hardware.fr/user/delflag.php?",
        "/user/delflag.php.evil?", "/user/xdelflag.php?", "/user/delflag.php/x?"
    ])
    func foreignLinkIsRefused(prefix: String) throws {
        let html = try Fixture.capture("R21-topic-p1-logged-in")
        let edited = html.replacing(#"<a href="/user/delflag.php?"#, with: #"<a href=""# + prefix)
        try #require(edited != html)
        #expect(try flag(html: edited) == nil)
    }

    @Test(
        "An absolute link to the forum is the same link (http without a port is read as https, ADR 0006 amendment 1)",
        arguments: ["https://forum.hardware.fr/user/delflag.php?", "http://forum.hardware.fr/user/delflag.php?"]
    )
    func absoluteLink(prefix: String) throws {
        let html = try Fixture.capture("R21-topic-p1-logged-in")
        let url = try #require(URL(string: Self.removal + Self.pizza))
        let absolute = html.replacing(#"<a href="/user/delflag.php?"#, with: #"<a href=""# + prefix)
        try #require(absolute != html)
        #expect(try flag(html: absolute) == TopicPageFlag(flag: .red, removalURL: url))
    }

    @Test("An unknown icon keeps the link without a flag")
    func unknownIcon() throws {
        let html = try Fixture.capture("R21-topic-p1-logged-in")
        let url = try #require(URL(string: Self.removal + Self.pizza))
        let otherIcon = html.replacing("/flagn0.gif", with: "/flagn9.gif")
        try #require(otherIcon != html)
        #expect(try flag(html: otherIcon) == TopicPageFlag(flag: nil, removalURL: url))
    }
}
