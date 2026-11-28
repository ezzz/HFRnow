import Foundation
import HFRModels
import Testing
@testable import HFRNetwork

/// Real redirects and cancellation against a loopback server standing in for the forum.
struct PageFetcherLoopbackTests {
    private let topic = TopicID(category: .forum(13), topic: 148_745)

    @Test func topicPageFollowsTheRedirectAndReadsTheCanonicalPage() async throws {
        let canonical = "/hfr/Programmation/Divers-6/hfr-android-sujet_148745_3.htm"
        let server = try LoopbackServer { request in
            if request.path.hasPrefix("/forum2.php") { return ServerReply(status: 301, headers: ["Location": canonical]) }
            return ServerReply(headers: ["Content-Type": "text/html; charset=iso-8859-1"], body: Data([0x63, 0x61, 0x66, 0xE9]))
        }
        defer { server.stop() }
        let transport = RewritingTransport(base: server.baseURL)
        let fetcher = PageFetcher(session: transport, anonymous: transport)
        let result = try await fetcher.topicPage(topic: topic, page: 3)
        #expect(result.page.finalURL.path == canonical)
        #expect(result.location == TopicPageLocation(topic: 148_745, page: 3))
        #expect(result.requestedPage == 3)
        #expect(result.page.text == "café")
        #expect(result.page.declaredCharset == "iso-8859-1")
        #expect(server.requests.first?.path == "/forum2.php?config=hfr.inc&cat=13&post=148745&page=3")
    }

    /// #1394: HFR's redirect chain as the loopback plays it (R5: `forum2.php` → 301 → canonical page → 200). The first page goes
    /// through `forum2.php`; the next one, asked from the page served, is one request, not two.
    @Test func theNextPageFromTheServedOneIsOneRequest() async throws {
        let canonical = "/hfr/Programmation/Divers-6/hfr-android-sujet_148745_"
        let server = try LoopbackServer { request in
            if request.path.hasPrefix("/forum2.php"), let page = request.path.split(separator: "=").last {
                return ServerReply(status: 301, headers: ["Location": canonical + page + ".htm"])
            }
            return ServerReply(headers: ["Content-Type": "text/html; charset=utf-8"], body: Data("ok".utf8))
        }
        defer { server.stop() }
        let transport = RewritingTransport(base: server.baseURL)
        let fetcher = PageFetcher(session: transport, anonymous: transport)
        let first = try await fetcher.topicPage(topic: topic, page: 1)
        #expect(server.requests.count == 2)
        // The app keeps the served page on the forum origin (`ReaderTarget.forumURL`); the loopback only stands in for it.
        let served = try #require(URL(string: "https://forum.hardware.fr" + first.page.finalURL.path))
        let second = try await fetcher.topicPage(topic: topic, page: 2, servedAt: served)
        #expect(server.requests.count == 3)
        #expect(server.requests.last?.path == canonical + "2.htm")
        #expect(second.location == TopicPageLocation(topic: 148_745, page: 2))
        #expect(second.requestedPage == 2)
    }

    @Test func aPageClampedByTheServerShowsInTheLocation() async throws {
        let server = try LoopbackServer { request in
            request.path.hasPrefix("/forum2.php")
                ? ServerReply(status: 301, headers: ["Location": "/hfr/Discussions/x-sujet_148745_7.htm"]) : ServerReply()
        }
        defer { server.stop() }
        let transport = RewritingTransport(base: server.baseURL)
        let result = try await PageFetcher(session: transport, anonymous: transport).topicPage(topic: topic, page: 99)
        #expect(result.location?.page == 7)
        #expect(result.requestedPage == 99)
    }

    @Test func cancellingAnInFlightFetchThrowsCancelled() async throws {
        let server = try LoopbackServer { _ in ServerReply(hangs: true) }
        defer { server.stop() }
        let transport = RewritingTransport(base: server.baseURL)
        let fetcher = PageFetcher(session: transport, anonymous: transport)
        let task = Task { try await fetcher.home() }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        await #expect(throws: NetworkError.cancelled) { try await task.value }
    }
}
