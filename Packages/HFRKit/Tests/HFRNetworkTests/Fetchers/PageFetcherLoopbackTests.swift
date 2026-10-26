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
