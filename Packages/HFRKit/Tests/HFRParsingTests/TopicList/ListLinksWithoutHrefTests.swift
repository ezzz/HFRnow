import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// Issue #102: a link without `href` in a list page made legacy raise on `nil` (`initWithString:` in
/// `ObjCTopicListParser.m:195`, `:214` pager, `:323` title, `:342` flag, `:417` last post, `:455` last page) and lose the
/// whole page. Here the entry is dropped and the rest of the page is kept. Pages are captures whose targets are removed
/// in memory. The home page and the favourites are covered by `ForumListRobustnessTests` and `FavoritesParserTests`.
@Suite("List links without href (#102)")
struct ListLinksWithoutHrefTests {
    static let listURL = "/hfr/Discussions/liste_sujet-1.htm"
    static let privateMessagesURL = "/forum1.php?config=hfr.inc&cat=prive&page=1"

    // MARK: - Pager

    @Test("A pager whose links have no target keeps the rows and the page numbers, and loses only the paths", arguments: [
        ("R04-list-cat13-p1-anon", "/hfr/Discussions/liste_sujet-1.htm"),
        ("R05a-list-cat13-p12-anon", "/hfr/Discussions/liste_sujet-12.htm"),
        ("R05b-list-cat13-p500-anon", "/hfr/Discussions/liste_sujet-500.htm"),
        ("R13u1-mp-list-recipient-unread", "/forum1.php?config=hfr.inc&cat=prive&page=1")
    ])
    func pagerWithoutTargets(capture: String, pageURL: String) throws {
        let original = try Fixture.capture(capture)
        let reference = try TopicListParser.parse(original, pageURL: pageURL)
        try #require(reference.navigation.nextPath != nil && reference.navigation.lastPath != nil)

        let page = try TopicListParser.parse(Self.withoutPagerTargets(original), pageURL: pageURL)
        #expect(page.topics == reference.topics)
        var expected = reference.navigation
        // The current page is a bold entry, not a link: it keeps the page's own path.
        if expected.first != expected.current { expected.firstPath = nil }
        if expected.last != expected.current { expected.lastPath = nil }
        expected.nextPath = nil
        expected.previousPath = nil
        #expect(page.navigation == expected)
    }

    // MARK: - Rows

    @Test("A title link without href drops its row only")
    func titleLinkWithoutHref() throws {
        let link = #"<a href="/hfr/Discussions/message-important-quittes-sujet_121557_1.htm" class="cCatTopic""#
        let (reference, page) = try Self.parse("R04-list-cat13-p1-anon", url: Self.listURL, removingHrefOf: link)
        #expect(page.topics == Array(reference.topics.dropFirst()))
    }

    @Test("A last-page link without href leaves its row on one page")
    func lastPageLinkWithoutHref() throws {
        let link = #"<a href="/hfr/Discussions/message-important-quittes-sujet_121557_84.htm" class="cCatTopic""#
        let (reference, page) = try Self.parse("R04-list-cat13-p1-anon", url: Self.listURL, removingHrefOf: link)
        let row = try #require(page.topics.first)
        #expect(reference.topics.first?.pageCount == 84)
        #expect(row.pageCount == 1)
        #expect(row.lastPagePath == row.path)
        #expect(row.topicID == reference.topics.first?.topicID)
        #expect(page.topics.dropFirst() == reference.topics.dropFirst())
    }

    @Test("A last-post link without href leaves its row without a last post")
    func lastPostLinkWithoutHref() throws {
        let link = #"<a href="/hfr/Discussions/message-important-quittes-sujet_121557_84.htm#bas" class="Tableau""#
        let (reference, page) = try Self.parse("R04-list-cat13-p1-anon", url: Self.listURL, removingHrefOf: link)
        let row = try #require(page.topics.first)
        #expect(reference.topics.first?.lastPost != nil)
        #expect(row.lastPost == nil)
        #expect(row.pageCount == 84)
        #expect(page.topics.dropFirst() == reference.topics.dropFirst())
    }

    @Test("A flag link without href leaves its row without a resume point")
    func flagLinkWithoutHref() throws {
        let url = "/forum1.php?config=hfr.inc&cat=13&page=1&subcat=&owntopic=2"
        let original = try Fixture.capture("R08-2-list-cat13-owntopic2")
        let mutated = original.replacing(#/<td class="sujetCase5"><a href="[^"]*"/#, with: #"<td class="sujetCase5"><a"#)
        try #require(mutated != original)
        let reference = try #require(TopicListParser.parse(original, pageURL: url).topics.first)
        let page = try TopicListParser.parse(mutated, pageURL: url)
        let row = try #require(page.topics.first)
        #expect(page.topics.count == 1)
        #expect(reference.flagPath != nil && reference.currentPage == 2)
        #expect(row.flagPath == nil)
        #expect(row.currentPage == nil)
        #expect(row.topicID == reference.topicID)
        #expect(row.path == reference.path)
    }

    @Test("MP list: a thread whose title link has no href is dropped, the others stay")
    func privateMessageTitleWithoutHref() throws {
        let original = try Fixture.capture("R13u1-mp-list-recipient-unread")
        let mutated = original.replacing(
            #/<a href="[^"]*" class="cCatTopic" title="Sujet n°3207033">/#,
            with: #"<a class="cCatTopic" title="Sujet n°3207033">"#
        )
        try #require(mutated != original)
        let reference = try PrivateMessageListParser.parse(original, pageURL: Self.privateMessagesURL)
        let page = try PrivateMessageListParser.parse(mutated, pageURL: Self.privateMessagesURL)
        let others = reference.threads.filter { $0.summary.topicID?.topic != 3_207_033 }
        #expect(others.count == reference.threads.count - 1)
        #expect(page.threads == others)
        #expect(page.navigation == reference.navigation)
    }

    // MARK: - Helpers

    /// Parses a capture as served and with the `href` of `link` (the start of one `<a …` tag, found exactly once) removed.
    private static func parse(
        _ capture: String,
        url: String,
        removingHrefOf link: String
    ) throws -> (reference: TopicListPage, page: TopicListPage) {
        let original = try Fixture.capture(capture)
        try #require(original.ranges(of: link).count == 1)
        let mutated = original.replacing(link, with: link.replacing(#/href="[^"]*" /#, with: ""))
        return (try TopicListParser.parse(original, pageURL: url), try TopicListParser.parse(mutated, pageURL: url))
    }

    /// The page with every link of the top pager (`tr.fondForum1PagesHaut`) turned into an `<a>` without `href`:
    /// obfuscated `span.md_cryptlink…` entries and arrows as well as plain `a.cHeader` entries.
    private static func withoutPagerTargets(_ html: String) throws -> String {
        let start = try #require(html.range(of: "fondForum1PagesHaut"))
        let end = try #require(html.range(of: "</tr>", range: start.upperBound..<html.endIndex))
        let pager = html[start.lowerBound..<end.upperBound]
        let stripped = String(pager)
            .replacing(#/<span class="md_cryptlink[0-9A-Fa-f]*">([^<]*)</span>/#) { "<a class=\"cHeader\">\($0.output.1)</a>" }
            .replacing(#/<a href="[^"]*" class="cHeader">/#, with: #"<a class="cHeader">"#)
        try #require(stripped != String(pager))
        try #require(!stripped.contains("md_cryptlink") && !stripped.contains("href="))
        return html.replacingCharacters(in: start.lowerBound..<end.upperBound, with: stripped)
    }
}
