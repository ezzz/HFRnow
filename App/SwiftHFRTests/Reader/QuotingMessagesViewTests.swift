import Foundation
import HFRModels
import HFRNetwork
import HFRParsing
@testable import SwiftHFR
import Testing

/// #1039: « Message cité N fois » opens the page of the messages that quote this one (`quote_only=1`, capture `R126a`, HFR-PROTOCOL
/// §6c « Batch A »), through the account session, in the shape captured.
@MainActor
struct QuotingMessagesViewTests {
    private static let topic = TopicID(category: .forum(13), topic: 28_563)
    private static let quotingLink = HFRQuotingLink(topic: topic, subcategory: 433, numreponse: 35_643_367)
    private static let linkText = "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&subcat=433&post=28563&page=1&p=1&sondage="
        + "&owntopic=&trash=&trash_post=&print=&numreponse=35643367&quote_only=1&new=0&nojs=0"

    // MARK: The page

    /// `R126a` parses with the ordinary chain: the two messages that quote the cited one, no pager.
    @Test func theCapturedPageParsesAsTwoMessagesWithoutPager() throws {
        let page = try LiveTopicPageSourceTests.readerPage(of: "R126a-topic-quote-only-list-anon.html")
        #expect(page.messages.count == 2)
        #expect(page.maxPage == 1)
        #expect(page.currentPage == 1)
    }

    /// The session asks for exactly `R126a`'s request, not the link as it was written and not the topic page.
    @Test func theSourceAsksTheQuoteViewThroughTheSession() async throws {
        let body = try LiveTopicPageSourceTests.capture("R126a-topic-quote-only-list-anon.html")
        let session = MockTransport { _ in
            HTTPResponse(statusCode: 200, headers: ["Content-Type": "text/html; charset=utf-8"], url: url(Self.linkText), body: body)
        }
        let anonymous = MockTransport(replies: [])
        let source = LiveTopicPageSource(
            fetcher: PageFetcher(session: session, anonymous: anonymous), session: session, normalizer: LiveContentNormalizer()
        )
        let page = try await source.page(for: ReaderTarget(source: .quotingMessages(Self.quotingLink)))
        #expect(await session.requests.map(\.url.absoluteString) == [Self.linkText])
        #expect(await anonymous.requests.isEmpty)
        #expect(page.messages.count == 2)
    }

    // MARK: The tap

    private func reader(on target: ReaderTarget, pages: FakeTopicPages = FakeTopicPages()) -> TopicReaderModel {
        TopicReaderModel(target: target, title: "Sujet", source: pages)
    }

    /// A tap on the bubble's link opens the quote view in the app, never the browser (before #1039 the router sent it there).
    @Test func tappingTheBubbleOpensTheQuoteViewInTheApp() throws {
        let model = reader(on: ReaderTarget(source: .topic(readerTopic)))
        let action = model.action(forLink: try #require(URL(string: Self.linkText)), defaultBrowser: false)
        #expect(action == .reader(ReaderTarget(source: .quotingMessages(Self.quotingLink))))
    }

    @Test func aQuoteViewOfAnotherHostIsNotOpenedInTheApp() throws {
        let model = reader(on: ReaderTarget(source: .topic(readerTopic)))
        let other = try #require(URL(string: Self.linkText.replacingOccurrences(of: "forum.hardware.fr", with: "example.org")))
        #expect(model.action(forLink: other, defaultBrowser: false) == .inAppBrowser(other))
    }

    /// A refresh of the quote view asks for the quote view again, not for the whole topic.
    @Test func theQuoteViewKeepsItsSourceAfterTheLoadAndTheRefresh() async {
        let pages = FakeTopicPages()
        let target = ReaderTarget(source: .quotingMessages(Self.quotingLink))
        let model = reader(on: target, pages: pages)
        await model.onAppear()
        #expect(model.shown?.source == .quotingMessages(Self.quotingLink))
        await model.refresh()
        #expect(pages.requests.map(\.source) == [.quotingMessages(Self.quotingLink), .quotingMessages(Self.quotingLink)])
    }
}
