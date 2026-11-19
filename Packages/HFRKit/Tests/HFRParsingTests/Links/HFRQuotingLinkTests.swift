import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// #1039: the « Message cité N fois » link (`quote_only=1`) read into the values a request is rebuilt from, and the shapes refused.
struct HFRQuotingLinkTests {
    /// The `href` of `R353a`'s `div.edited` link (anonymized ids), `&amp;` decoded as the parser hands it over.
    static let link = "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&subcat=433&post=28563&page=1&p=1&sondage=&owntopic="
        + "&trash=&trash_post=&print=&numreponse=35632185&quote_only=1&new=0&nojs=0"

    private func parse(_ string: String) throws -> HFRQuotingLink? {
        HFRQuotingLink(url: try #require(URL(string: string)))
    }

    @Test func theCapturedLinkGivesTopicSubcategoryAndMessage() throws {
        let parsed = try #require(try parse(Self.link))
        #expect(parsed == HFRQuotingLink(topic: TopicID(category: .forum(13), topic: 28563), subcategory: 433, numreponse: 35_632_185))
    }

    @Test func anEmptySubcategoryIsNone() throws {
        let parsed = try #require(try parse(Self.link.replacingOccurrences(of: "subcat=433", with: "subcat=")))
        #expect(parsed.subcategory == nil)
    }

    /// The parser hands the link over absolute (`HFRURL.absolute`); a relative link must be resolved first.
    @Test func theHrefAsTheParserHandsItOverIsRead() throws {
        let absolute = try #require(HFRURL.absolute("/forum2.php?config=hfr.inc&cat=13&post=5&numreponse=9&quote_only=1&new=0&nojs=0"))
        #expect(HFRQuotingLink(url: absolute)?.numreponse == 9)
    }

    @Test(arguments: [
        "https://example.org/forum2.php?config=hfr.inc&cat=13&post=5&numreponse=9&quote_only=1",
        "https://forum.hardware.fr:8443/forum2.php?config=hfr.inc&cat=13&post=5&numreponse=9&quote_only=1",
        "https://forum.hardware.fr/forum2.php?config=other&cat=13&post=5&numreponse=9&quote_only=1",
        "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=5&numreponse=9&quote_only=0",
        "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=5&numreponse=9",
        "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=5&numreponse=0&quote_only=1",
        "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=5&quote_only=1",
        "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=0&post=5&numreponse=9&quote_only=1",
        "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&numreponse=9&quote_only=1",
        "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=5&numreponse=9&quote_only=1&subcat=x",
        "https://forum.hardware.fr/forum1.php?config=hfr.inc&cat=13&post=5&numreponse=9&quote_only=1",
        // A private thread's quote view was never captured: its shape is not guessed (#1039).
        "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=prive&post=5&numreponse=9&quote_only=1"
    ])
    func otherLinksAreRefused(link: String) throws {
        #expect(try parse(link) == nil)
    }

    /// A normal topic link, and a print view, are not quote views.
    @Test func plainTopicLinksAreNotQuoteViews() throws {
        #expect(try parse("https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=5&page=2") == nil)
        #expect(try parse("https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=5&print=1&numreponse=9") == nil)
    }
}
