import Foundation
import Testing
@testable import HFRParsing

/// LOT-058: the "mark as unread" link of a private conversation, read from the page header (`RA1`-`RA4`), never from
/// a message or another origin.
@Suite("Mark-unread link")
struct MarkUnreadLinkTests {
    private static let expected = "https://forum.hardware.fr/user/nonlu.php?config=hfr.inc&cat=prive&subcat=0&post=3207033"
        + "&page=1&p=1&sondage=0&owntopic=0&new=0"

    private static func link(in html: String) throws -> URL? {
        try TopicPageMetadataParser.parse(html: html, pageURL: "/forum2.php?config=hfr.inc&cat=prive&post=3207033&page=1")
            .markUnreadURL
    }

    @Test("Each captured conversation page carries the link, as W18 requested it", arguments: [
        "RA1-mp-thread-after-create", "RA2-mp-thread-crlf-lf-nonbmp", "RA3-mp-thread-before-cleanup", "RA4-mp-thread-both-accounts"
    ])
    func conversations(file: String) throws {
        #expect(try Self.link(in: try Fixture.capture(file))?.absoluteString == Self.expected)
    }

    @Test("Topic pages and a deleted conversation have none", arguments: [
        "R20-topic-p1-anon", "R21-topic-p1-logged-in", "RA5-mp-thread-after-delete-owner"
    ])
    func noLink(file: String) throws {
        #expect(try Self.link(in: try Fixture.capture(file)) == nil)
    }

    @Test("Only a header link on the forum origin with the exact path counts (small fragments: the rule's inputs)")
    func origin() throws {
        let path = "/user/nonlu.php?config=hfr.inc&amp;cat=prive&amp;post=3207033"
        #expect(try Self.link(in: "<a href=\"\(path)\" class=\"cLink\">posté dans un message</a>") == nil)
        #expect(try Self.link(in: "<a href=\"https://example.org\(path)\" class=\"cHeader\">x</a>") == nil)
        #expect(try Self.link(in: "<a href=\"https://forum.hardware.fr:8443\(path)\" class=\"cHeader\">x</a>") == nil)
        #expect(try Self.link(in: "<a href=\"/user/nonlu.php.bak?cat=prive\" class=\"cHeader\">x</a>") == nil)
        #expect(try Self.link(in: "<span href=\"\(path)\" class=\"cHeader\">x</span>") == nil)
        let link = try #require(try Self.link(in: "<a href=\"\(path)\" class=\"cHeader\">x</a>"))
        #expect(link.absoluteString == "https://forum.hardware.fr/user/nonlu.php?config=hfr.inc&cat=prive&post=3207033")
    }
}
