import Foundation
import HFRModels
import HFRNetwork
import Testing
@testable import HFRClient

/// The global search flow over the captured exchange: `R50a` (waiting page) then `R50b` / `R50c` (results).
@Suite("Global search (LOT-046)")
struct GlobalSearchFlowTests {
    /// `R50a`'s query: legacy defaults, the text as captured (`request_body`), the token as anonymised.
    static let pizza = GlobalSearchQuery(text: "pizza napolitaine")
    static let token = "REDACTED"

    private static func run(
        _ query: GlobalSearchQuery = pizza, replies: [Result<HTTPResponse, NetworkError>]
    ) async -> (result: Result<GlobalSearchResult, GlobalSearchError>, requests: [HTTPRequest]) {
        let transport = MockTransport(replies: replies)
        let result: Result<GlobalSearchResult, GlobalSearchError>
        do {
            result = .success(try await GlobalSearchFlow(transport: transport).search(query, hashCheck: token))
        } catch {
            result = .failure(error)
        }
        return (result, await transport.requests)
    }

    @Test("R50a then R50b: the legacy body, the oracle's results URL by GET, the oracle's rows, no cookie")
    func resultsMatchTheOracles() async throws {
        let waiting = try SearchCapture.answer("R50a-search-post-waiting-page", id: "R50a")
        let results = try SearchCapture.answer("R50b-search-results-no-cookie", id: "R50b")
        let (result, requests) = await Self.run(replies: [.success(waiting), .success(results)])
        let page = try result.get()

        let meta = try Capture.meta("R50a")
        #expect(requests.count == 2)
        let post = try #require(requests.first)
        #expect(post.method == .post)
        #expect(post.url.absoluteString == meta.url)
        #expect(SearchCapture.body(of: post) == meta.requestBody)
        let redirect = try SearchCapture.oracle("LOT-005", "R50a")
        let get = try #require(requests.last)
        #expect(get.method == .get)
        #expect(get.url.absoluteString == redirect["absoluteURL"] as? String)
        #expect(get.body == nil)
        #expect(requests.allSatisfy { $0.headers["Cookie"] == nil })

        let legacy = try SearchCapture.oracle("LOT-002", "R50b")
        let rows = try #require(legacy["topics"] as? [[String: Any]])
        #expect(page.url.absoluteString == (try Capture.meta("R50b")).finalURL)
        #expect(page.page.topics.count == rows.count)
        #expect(page.page.topics.map(\.path) == rows.compactMap { $0["aURL"] as? String })
        #expect(page.page.navigation.nextPath == legacy["nextPageUrl"] as? String)
        #expect(page.page.notice == nil)
    }

    @Test("R50c: no result is an empty page with HFR's notice, not an error")
    func noResultIsAnEmptyPage() async throws {
        let waiting = try SearchCapture.answer("R50a-search-post-waiting-page", id: "R50a")
        let empty = try SearchCapture.answer("R50c-search-no-result-no-cookie", id: "R50c")
        let (result, requests) = await Self.run(replies: [.success(waiting), .success(empty)])
        let page = try result.get()
        let legacy = try SearchCapture.oracle("LOT-002", "R50c")
        let status = try #require(legacy["statusInfo"] as? [String: Any])
        #expect(page.page.topics.isEmpty)
        #expect(page.page.notice == status["message"] as? String)
        #expect(requests.count == 2)
    }

    @Test(
        "A banned word refuses the search before any request (Q-7)",
        arguments: [
            ("jailbreak", "jailbreak"),
            ("Mon JailBreak", "jailbreak"),
            ("CYDIA", "cydia"),
            ("penguin", "pengu"),
            ("apple jb tweak", "apple jb")
        ]
    )
    func bannedWord(text: String, word: String) async throws {
        let (result, requests) = await Self.run(GlobalSearchQuery(text: text), replies: [])
        #expect(result == .failure(.bannedWord(word)))
        #expect(requests.isEmpty)
    }

    @Test("Text near a banned word is searched as typed")
    func nearBannedWordIsSearched() async throws {
        let (_, requests) = await Self.run(GlobalSearchQuery(text: "applejb"), replies: [.failure(.offline)])
        #expect(requests.count == 1)
        let post = try #require(requests.first)
        #expect(SearchCapture.body(of: post)?.contains("search=applejb&") == true)
    }

    @Test("Accented text leaves UTF-8 percent-encoded (legacy sent it raw)")
    func accentedTextIsPercentEncoded() async throws {
        let (result, requests) = await Self.run(GlobalSearchQuery(text: "Pâtes à l'ail"), replies: [.failure(.offline)])
        #expect(result == .failure(.network(.offline)))
        let post = try #require(requests.first)
        let body = try #require(SearchCapture.body(of: post))
        #expect(body.contains("&search=p%C3%A2tes+%C3%A0+l%27ail&"))
    }

    @Test("A waiting page without refresh is 'no results page', and nothing else is requested")
    func noRefresh() async throws {
        let empty = try SearchCapture.answer("R50c-search-no-result-no-cookie", id: "R50c")
        let (result, requests) = await Self.run(replies: [.success(empty)])
        #expect(result == .failure(.noResultsPage(.missingElement("meta http-equiv=refresh"))))
        #expect(requests.count == 1)
        let legacy = try SearchCapture.oracle("LOT-005", "R50c")
        #expect(legacy["hasRedirect"] as? Bool == false)
    }

    @Test("Results served off the forum are not HFR's")
    func resultsOffTheForum() async throws {
        let waiting = try SearchCapture.answer("R50a-search-post-waiting-page", id: "R50a")
        let elsewhere = try Capture.response(
            "R50b-search-results-no-cookie", url: try #require(URL(string: "https://example.com/forum1.php?recherches=1"))
        )
        let (result, _) = await Self.run(replies: [.success(waiting), .success(elsewhere)])
        #expect(result == .failure(.page(.malformed("search results served off the forum"))))
    }

    @Test(
        "Failures are reported once: the POST is never retried, a failed GET is not replaced by another",
        arguments: [NetworkError.timedOut, .offline]
    )
    func transportFailures(failure: NetworkError) async throws {
        let first = await Self.run(replies: [.failure(failure)])
        #expect(first.result == .failure(.network(failure)))
        #expect(first.requests.count == 1)
        let waiting = try SearchCapture.answer("R50a-search-post-waiting-page", id: "R50a")
        let second = await Self.run(replies: [.success(waiting), .failure(failure)])
        #expect(second.result == .failure(.network(failure)))
        #expect(second.requests.count == 2)
    }

    @Test("An HTTP error on the results is a network failure")
    func httpError() async throws {
        let waiting = try SearchCapture.answer("R50a-search-post-waiting-page", id: "R50a")
        let target = try #require(try SearchCapture.oracle("LOT-005", "R50a")["absoluteURL"] as? String)
        let url = try #require(URL(string: target))
        let (result, _) = await Self.run(replies: [.success(waiting), .success(HTTPResponse(statusCode: 503, url: url))])
        #expect(result == .failure(.network(.httpStatus(code: 503, url: url))))
    }

    @Test("An empty text is refused before any request")
    func emptyText() async throws {
        let (result, requests) = await Self.run(GlobalSearchQuery(text: "  "), replies: [])
        #expect(result == .failure(.network(.invalidRequest(reason: "empty search text"))))
        #expect(requests.isEmpty)
    }

    @Test("A search cancelled while its POST is in flight never sends the GET")
    func cancelledBetweenPostAndGet() async throws {
        let waiting = try SearchCapture.answer("R50a-search-post-waiting-page", id: "R50a")
        let transport = MockTransport { _ async throws(NetworkError) -> HTTPResponse in
            withUnsafeCurrentTask { $0?.cancel() }
            return waiting
        }
        let task = Task { () async -> GlobalSearchError? in
            do throws(GlobalSearchError) {
                _ = try await GlobalSearchFlow(transport: transport).search(Self.pizza, hashCheck: Self.token)
                return nil
            } catch {
                return error
            }
        }
        #expect(await task.value == .network(.cancelled))
        #expect(await transport.requests.map(\.method) == [.post])
    }

    @Test("A pager path of the results is fetched by GET, without cookie")
    func nextPage() async throws {
        let path = try #require(try SearchCapture.oracle("LOT-002", "R50b")["nextPageUrl"] as? String)
        let transport = MockTransport(replies: [.failure(.offline)])
        await #expect(throws: GlobalSearchError.network(.offline)) {
            try await GlobalSearchFlow(transport: transport).page(atPath: path)
        }
        let requests = await transport.requests
        #expect(requests.map(\.url.absoluteString) == ["https://forum.hardware.fr" + path])
        #expect(requests.allSatisfy { $0.method == .get && $0.headers["Cookie"] == nil })
    }

    @Test(
        "A path that is not a search results page of the forum is never requested",
        arguments: [
            "https://example.com/forum1.php?recherches=1&page=2",
            "http://forum.hardware.fr:80/forum1.php?recherches=1&page=2",
            "https://forum.hardware.fr:8443/forum1.php?recherches=1&page=2",
            "/forum2.php?config=hfr.inc&cat=13&post=28563&recherches=1",
            "/forum1.php?config=hfr.inc&cat=13&page=2",
            "/forum1.php?config=hfr.inc&cat=13&page=2&recherches=0",
            "javascript:alert(1)"
        ]
    )
    func invalidPage(path: String) async throws {
        let transport = MockTransport(replies: [])
        await #expect(throws: GlobalSearchError.invalidPage(path)) {
            try await GlobalSearchFlow(transport: transport).page(atPath: path)
        }
        #expect(await transport.requests.isEmpty)
    }

    @Test("The public flow sends everything through a cookie-less transport")
    func publicFlowIsCookieless() {
        #expect(GlobalSearchFlow().transport is AnonymousTransport)
    }
}
