import Foundation
import HFRModels
import HFRNetwork
import HFRParsing
@testable import SwiftHFR
import Testing

/// The live source: the list goes through the account session, then LOT-023's parser, on the captured MP lists.
struct LivePrivateMessageSourceTests {
    private func source(replying body: Data, session: MockTransport? = nil) -> (LivePrivateMessageSource, MockTransport, MockTransport) {
        let session = session ?? MockTransport { request async throws(NetworkError) -> HTTPResponse in
            HTTPResponse(statusCode: 200, headers: ["Content-Type": "text/html; charset=utf-8"], url: request.url, body: body)
        }
        let anonymous = MockTransport(replies: [])
        return (LivePrivateMessageSource(fetcher: PageFetcher(session: session, anonymous: anonymous)), session, anonymous)
    }

    @Test func theCapturedListIsFetchedWithTheSessionAndParsed() async throws {
        let body = try LiveTopicPageSourceTests.capture("R13u1-mp-list-recipient-unread.html")
        let (source, session, anonymous) = source(replying: body)
        let page = try await source.privateMessages(page: 2)
        let requests = await session.requests
        #expect(requests.count == 1)
        let expected = "https://forum.hardware.fr/forum1.php?config=hfr.inc&cat=prive&page=2"
        #expect(requests.first?.url.absoluteString.hasPrefix(expected) == true)
        #expect(await anonymous.requests.isEmpty)
        let listURL = "https://forum.hardware.fr/forum1.php?config=hfr.inc&cat=prive&page=2"
        let oracle = try PrivateMessageListParser.parse(try #require(String(data: body, encoding: .utf8)), pageURL: listURL)
        #expect(page.threads.count == oracle.threads.count)
        #expect(page.threads.contains { $0.isGroup })
        #expect(page.threads.contains { $0.isUnread })
        #expect(page.threads.allSatisfy { ReaderTarget(opening: $0.summary) != nil })
    }

    @Test func aListOfAnotherCategoryIsUnreadableNotShownAsMessages() async throws {
        let body = try LiveTopicPageSourceTests.capture("R04-list-cat13-p1-anon.html")
        let (source, _, _) = source(replying: body)
        do throws(ListLoadError) {
            _ = try await source.privateMessages(page: 1)
            Issue.record("expected a failure")
        } catch {
            #expect(error == .unreadable)
        }
    }

    @Test func aTransportFailureIsMapped() async {
        let session = MockTransport { _ async throws(NetworkError) -> HTTPResponse in throw .offline }
        let (source, _, _) = source(replying: Data(), session: session)
        do throws(ListLoadError) {
            _ = try await source.privateMessages(page: 1)
            Issue.record("expected a failure")
        } catch {
            #expect(error == .offline)
        }
    }
}
