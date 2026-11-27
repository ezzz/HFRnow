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

    @Test("Each page is the page asked for: current page from the URL, 4 pages in the pager, the conversation's identity")
    func metadataNamesThePage() throws {
        for capture in Self.pages {
            let page = try TopicPageMetadataParser.parse(html: Capture.page(capture.file), pageURL: Capture.meta(capture.id).url)
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

    @Test("A page=1 link naming a message of page 3 answers 200 in place, no Location (R1315c, the R388a shape)")
    func messageLinkOnALaterPageIsServedInPlace() throws {
        let meta = try Capture.meta("R1315c")
        let third = try MessageBlockParser.blocks(in: Capture.page(Self.pages[1].file)).map(\.numreponse)
        let components = try #require(URLComponents(string: meta.url))
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
        #expect(query["page"] == "1")
        #expect(query["numreponse"] == String(third[1]))
        #expect(meta.status == 200)
        #expect(meta.redirects?.isEmpty ?? true)
        #expect(meta.finalURL == meta.url)
    }
}
