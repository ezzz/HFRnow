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
        let components = try #require(requests.first.flatMap { URLComponents(url: $0.url, resolvingAgainstBaseURL: false) })
        #expect(components.host == "forum.hardware.fr")
        #expect(components.path == "/forum1.php")
        let query = Dictionary(components.queryItems?.map { ($0.name, $0.value ?? "") } ?? [], uniquingKeysWith: { first, _ in first })
        #expect(query["cat"] == "prive")
        #expect(query["page"] == "2")
        #expect(await rig.anonymous.requests.isEmpty)
        let listURL = "https://forum.hardware.fr/forum1.php?config=hfr.inc&cat=prive&page=2"
        let oracle = try PrivateMessageListParser.parse(try #require(String(data: body, encoding: .utf8)), pageURL: listURL)
        #expect(page.threads.count == oracle.threads.count)
        #expect(page.threads.contains { $0.isGroup })
        #expect(page.threads.contains { $0.isUnread })
        #expect(page.threads.allSatisfy { ReaderTarget(opening: $0.summary) != nil })
    }

    /// The 457-page thread of `R13u1` (new post at `page=457…#bas`): the row opens the reader on its last page, and only
    /// showing that page marks it read. A title-link regression (page 1) fails here, where the fixtures are hand-made.
    @MainActor
    @Test func theCapturedLongThreadOpensOnItsLastPage() async throws {
        let rig = rig(replying: try LiveTopicPageSourceTests.capture("R13u1-mp-list-recipient-unread.html"))
        let page = try await rig.source.privateMessages(page: 1)
        let thread = try #require(page.threads.first { $0.summary.topicID == TopicID(category: .privateMessages, topic: 3197250) })
        #expect(thread.summary.pageCount == 457)
        let fake = FakePrivateMessages()
        fake.handler = { _ in page }
        let model = MessageListModel(source: fake, isLoggedIn: { true }, topicPages: FakeTopicPages())
        await model.onAppear()
        let reader = try #require(model.reader(for: thread))
        #expect(reader.requested.source == .topic(TopicID(category: .privateMessages, topic: 3197250)))
        #expect(reader.requested.page == 457)
        // The link ends in `#bas`: the conversation opens on its latest message, not at the top of the page.
        await reader.onAppear()
        #expect(reader.document?.anchor == 45_701)
        #expect(model.isUnread(thread))
        model.markOpened(thread, page: 1, of: 457)
        #expect(model.isUnread(thread))
        model.markOpened(thread, page: 457, of: 457)
        #expect(!model.isUnread(thread))
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
        let html = try #require(String(data: try LiveTopicPageSourceTests.capture("RA1-mp-thread-after-create.html"), encoding: .utf8))
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
