import Foundation
import HFRModels
import HFRNetwork
import HFRParsing
import Testing

/// #1315: the middle pages of a 4-page private conversation (`R1315a` page 2, `R1315b` page 3) and a `page=1` link naming a
/// message of page 3 (`R1315c`, meta only), checked against the URL « Page numéro… » of an MP row asks for (#1311, PR #1314).
@Suite("Private conversation middle pages")
struct PrivateThreadMiddlePageTests {
    static let thread = TopicID(category: .privateMessages, topic: 3_207_461)

    struct CapturedPage {
        let id: String
        let file: String
        let page: Int
    }

    static let pages = [
        CapturedPage(id: "R1315a", file: "R1315a-mp-thread-page-2-of-4", page: 2),
        CapturedPage(id: "R1315b", file: "R1315b-mp-thread-page-3-of-4", page: 3)
    ]

    @Test("« Page numéro… » asks for the captured URL; HFR answers 200 in place, no redirect")
    func pageNumberURLIsTheCapturedOne() throws {
        for capture in Self.pages {
            let meta = try Capture.meta(capture.id)
            #expect(try HFREndpoint.topicPage(topic: Self.thread, page: capture.page).url.absoluteString == meta.url)
            #expect(meta.status == 200)
            #expect(meta.redirects?.isEmpty ?? true)
            #expect(meta.finalURL == meta.url)
        }
    }

    /// The parser takes the current page from the URL, so the body's own page is read from its pager: HFR prints the current
    /// page in `<b>` after a link to the one before.
    @Test("Each page is the page asked for: its pager marks it current, 4 pages, the conversation's identity")
    func metadataNamesThePage() throws {
        for capture in Self.pages {
            let html = try Capture.page(capture.file)
            #expect(html.contains("class=\"cHeader\">\(capture.page - 1)</a>&nbsp;&nbsp;<b>\(capture.page)</b>&nbsp;"))
            let page = try TopicPageMetadataParser.parse(html: html, pageURL: Capture.meta(capture.id).url)
            #expect((page.currentPage, page.maxPage) == (capture.page, 4))
            #expect(page.topicID == Self.thread)
            #expect(page.answerFormFields["cat"] == "prive")
        }
    }

    /// The pages hold their own messages only, plus the copy of the previous page's last one that opens every page after
    /// the first (`R22a` on a public topic). The copy's « Reprise du message précédent » lead is message content, which the
    /// anonymizer replaces on a private page, so `isContinuation` cannot be read on these captures (HFR-PROTOCOL §6c #1315).
    @Test("Page 3 opens with page 2's last message, then 40 messages of its own, ascending")
    func pagesHoldTheirOwnMessages() throws {
        let second = try MessageBlockParser.blocks(in: Capture.page(Self.pages[0].file)).map(\.numreponse)
        let third = try MessageBlockParser.blocks(in: Capture.page(Self.pages[1].file)).map(\.numreponse)
        #expect(second.count == 41)
        #expect(third.count == 41)
        #expect(third.first == second.last)
        for numbers in [second, third] {
            #expect(numbers == numbers.sorted())
            #expect(Set(numbers).count == numbers.count)
        }
        #expect(Set(second).intersection(third) == [third[0]])
    }

    /// Each message's answer link numbers it on the page (`ref`); the copy that opens the page is `ref=0`, as on a public
    /// topic (HFR-PROTOCOL "Obfuscated quote link in practice").
    @Test("The first block's answer link is ref=0, the page's own messages ref=1…40")
    func continuationIsRefZero() throws {
        let link = /numrep=([0-9]+)&amp;ref=([0-9]+)&amp;page=([0-9]+)&amp;/
        for capture in Self.pages {
            let html = try Capture.page(capture.file)
            let blocks = try MessageBlockParser.blocks(in: html).map(\.numreponse)
            let matches = html.matches(of: link)
            #expect(matches.map { Int($0.1) } == blocks)
            #expect(matches.map { Int($0.2) } == Array(0...40))
            #expect(matches.allSatisfy { Int($0.3) == capture.page })
        }
    }

    @Test("A page=1 link naming a message of page 3 answers 200 in place, no Location (R1315c, the R388a shape)")
    func messageLinkOnALaterPageIsServedInPlace() throws {
        let meta = try Capture.meta("R1315c")
        let third = try MessageBlockParser.blocks(in: Capture.page(Self.pages[1].file)).map(\.numreponse)
        // The request the reader sends for a message link (`TopicPageSource.messageRequest`) is the captured one.
        #expect(try HFREndpoint.topicPage(topic: Self.thread, page: 1, numreponse: third[1]).url.absoluteString == meta.url)
        #expect(meta.status == 200)
        #expect(meta.redirects?.isEmpty ?? true)
        #expect(meta.finalURL == meta.url)
    }
}
