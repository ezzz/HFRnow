import Foundation
import HFRModels
import HFRNetwork
import HFRParsing
@testable import SwiftHFR
import Testing

/// The live source: the page the user opens goes through the account session (E25), then the LOT-030/033 parsers.
struct LiveTopicPageSourceTests {
    /// Captured topic pages of the LOT-001 corpus (anonymized), read from the engine's test fixtures.
    static func capture(_ name: String) throws -> Data {
        let captures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Packages/HFRKit/Tests/HFRParsingTests/Fixtures/captures")
        return try Data(contentsOf: captures.appending(path: name))
    }

    /// Normalizer double: marks the content so the test sees which blocks went through it.
    struct MarkingNormalizer: MessageContentNormalizing {
        func normalize(contentHTML: String, pageURL: URL) throws(ParsingError) -> MessageContent {
            MessageContent(html: "<p>normalized \(contentHTML.utf8.count)</p>")
        }
    }

    private static let canonical = "https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm"

    @Test func theOpenedPageGoesThroughTheSessionAndIsParsed() async throws {
        let body = try Self.capture("R20-topic-p1-anon.html")
        let session = MockTransport { _ in
            HTTPResponse(statusCode: 200, headers: ["Content-Type": "text/html; charset=utf-8"], url: url(Self.canonical), body: body)
        }
        let anonymous = MockTransport(replies: [])
        let source = LiveTopicPageSource(
            fetcher: PageFetcher(session: session, anonymous: anonymous), session: session, normalizer: MarkingNormalizer()
        )
        let page = try await source.page(for: ReaderTarget(source: .topic(readerTopic), page: 1, anchor: 5))
        let requests = await session.requests
        #expect(requests.count == 1)
        let expected = "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=28563&page=1"
        #expect(requests.first?.url.absoluteString.hasPrefix(expected) == true)
        #expect(await anonymous.requests.isEmpty)
        let blocks = try MessageBlockParser.blocks(in: try #require(String(data: body, encoding: .utf8)))
        #expect(page.messages.count == blocks.count)
        #expect(page.messages.map(\.numreponse) == blocks.map(\.numreponse))
        #expect(page.messages.allSatisfy { $0.content.html.hasPrefix("<p>normalized ") })
        #expect(page.topicID == readerTopic)
        #expect(page.currentPage == 1)
        #expect(!page.title.isEmpty)
    }

    @Test func aCanonicalPathIsFetchedOnTheForumWithTheSession() async throws {
        let body = try Self.capture("R20-topic-p1-anon.html")
        let session = MockTransport { request in
            HTTPResponse(statusCode: 200, headers: ["Content-Type": "text/html; charset=utf-8"], url: request.url, body: body)
        }
        let source = LiveTopicPageSource(
            fetcher: PageFetcher(session: session, anonymous: MockTransport(replies: [])), session: session,
            normalizer: MarkingNormalizer()
        )
        let page = try await source.page(for: ReaderTarget(source: .path("/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm")))
        #expect(await session.requests.map(\.url.absoluteString) == [Self.canonical])
        #expect(page.topicID == readerTopic)
    }

    @Test func aPathOffTheForumIsNeverRequested() async {
        let session = MockTransport(replies: [])
        let source = LiveTopicPageSource(
            fetcher: PageFetcher(session: session, anonymous: session), session: session, normalizer: MarkingNormalizer()
        )
        await #expect(throws: ListLoadError.other) {
            try await source.page(for: ReaderTarget(source: .path("https://evil.example/hfr/a/b-sujet_1_1.htm")))
        }
        #expect(await session.requests.isEmpty)
    }

    @Test func networkFailuresAreActionable() async {
        let session = MockTransport(replies: [.failure(.offline)])
        let source = LiveTopicPageSource(
            fetcher: PageFetcher(session: session, anonymous: session), session: session, normalizer: MarkingNormalizer()
        )
        await #expect(throws: ListLoadError.offline) {
            try await source.page(for: ReaderTarget(source: .topic(readerTopic)))
        }
    }

    @Test(arguments: ["R22a-topic-middle-page-anon.html", "R26-topic-quotes-smileys-anon.html", "R27-topic-spoilers-anon.html",
                      "R27b-topic-code-blocks-anon.html", "R28-topic-images-videos-anon.html", "R31-topic-locked-anon.html"])
    func realPagesBuildADocumentWithoutPageScript(_ name: String) throws {
        let html = try #require(String(data: try Self.capture(name), encoding: .utf8))
        let page = try LiveTopicPageSource.parse(html, pageURL: url(Self.canonical), normalizer: ContentNormalizer())
        #expect(!page.messages.isEmpty)
        let document = TopicHTMLBuilder.document(for: page, token: 1)
        #expect(!document.contains("<script"))
        #expect(document.firstMatch(of: /<[a-z]+[^>]*\son[a-z]+\s*=/) == nil)
    }
}
