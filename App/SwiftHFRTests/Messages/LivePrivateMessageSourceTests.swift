import Foundation
import HFRModels
import HFRNetwork
import HFRParsing
@testable import SwiftHFR
import Testing

/// The live source: the list goes through the account session, then LOT-023's parser, on the captured MP lists.
struct LivePrivateMessageSourceTests {
    private struct Rig {
        let source: LivePrivateMessageSource
        let session: MockTransport
        let anonymous: MockTransport
    }

    private func rig(replying body: Data, session: MockTransport? = nil) -> Rig {
        let session = session ?? MockTransport { request async throws(NetworkError) -> HTTPResponse in
            HTTPResponse(statusCode: 200, headers: ["Content-Type": "text/html; charset=utf-8"], url: request.url, body: body)
        }
        let anonymous = MockTransport(replies: [])
        let source = LivePrivateMessageSource(fetcher: PageFetcher(session: session, anonymous: anonymous))
        return Rig(source: source, session: session, anonymous: anonymous)
    }

    @Test func theCapturedListIsFetchedWithTheSessionAndParsed() async throws {
        let body = try LiveTopicPageSourceTests.capture("R13u1-mp-list-recipient-unread.html")
        let rig = rig(replying: body)
        let page = try await rig.source.privateMessages(page: 2)
        let requests = await rig.session.requests
        #expect(requests.count == 1)
        let expected = "https://forum.hardware.fr/forum1.php?config=hfr.inc&cat=prive&page=2"
        #expect(requests.first?.url.absoluteString.hasPrefix(expected) == true)
        #expect(await rig.anonymous.requests.isEmpty)
        let listURL = "https://forum.hardware.fr/forum1.php?config=hfr.inc&cat=prive&page=2"
        let oracle = try PrivateMessageListParser.parse(try #require(String(data: body, encoding: .utf8)), pageURL: listURL)
        #expect(page.threads.count == oracle.threads.count)
        #expect(page.threads.contains { $0.isGroup })
        #expect(page.threads.contains { $0.isUnread })
        #expect(page.threads.allSatisfy { ReaderTarget(opening: $0.summary) != nil })
    }

    @Test func aListOfAnotherCategoryIsUnreadableNotShownAsMessages() async throws {
        let body = try LiveTopicPageSourceTests.capture("R04-list-cat13-p1-anon.html")
        let rig = rig(replying: body)
        do throws(ListLoadError) {
            _ = try await rig.source.privateMessages(page: 1)
            Issue.record("expected a failure")
        } catch {
            #expect(error == .unreadable)
        }
    }

    /// `RA1` is the owner's MP thread page: the reader's parse (`LiveTopicPageSource.parse`) renders it like a topic page.
    @Test func anMPThreadPageRendersThroughTheReaderParser() throws {
        let html = String(decoding: try LiveTopicPageSourceTests.capture("RA1-mp-thread-after-create.html"), as: UTF8.self)
        let url = try #require(URL(string: "https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=prive&post=3207033&page=1"))
        let page = try LiveTopicPageSource.parse(html, pageURL: url, normalizer: LiveTopicPageSourceTests.MarkingNormalizer())
        let blocks = try MessageBlockParser.blocks(in: html)
        #expect(!page.messages.isEmpty)
        #expect(page.messages.map(\.numreponse) == blocks.map(\.numreponse))
        #expect(page.currentPage == 1)
        #expect(page.maxPage >= 1)
        #expect(!page.title.isEmpty)
    }

    @Test func aTransportFailureIsMapped() async {
        let session = MockTransport { _ async throws(NetworkError) -> HTTPResponse in throw .offline }
        let rig = rig(replying: Data(), session: session)
        do throws(ListLoadError) {
            _ = try await rig.source.privateMessages(page: 1)
            Issue.record("expected a failure")
        } catch {
            #expect(error == .offline)
        }
    }
}
