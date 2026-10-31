import Foundation
import HFRModels
import HFRNetwork
import HFRParsing
import Testing
@testable import HFRClient

/// The REST browsing client over scripted exchanges: the captured requests, the HTML fallback, no cookie (LOT-057).
@Suite("REST browsing client (LOT-057)")
struct RESTBrowsingClientTests {
    static let home = URL(string: "https://forum.hardware.fr/") ?? URL(fileURLWithPath: "/")
    static let list13 = URL(string: "https://forum.hardware.fr/hfr/Discussions/liste_sujet-1.htm") ?? URL(fileURLWithPath: "/")

    private static func run<Value>(
        _ replies: [Result<HTTPResponse, NetworkError>],
        _ call: (RESTBrowsingClient) async throws(RESTBrowsingError) -> Value
    ) async -> (result: Result<Value, RESTBrowsingError>, requests: [HTTPRequest]) {
        let transport = MockTransport(replies: replies)
        let result: Result<Value, RESTBrowsingError>
        do {
            result = .success(try await call(RESTBrowsingClient(transport: transport)))
        } catch {
            result = .failure(error)
        }
        return (result, await transport.requests)
    }

    /// A REST answer that is not the JSON: what HFR serves for an unknown resource is not captured, so any body will do.
    private static func notJSON(status: Int = 200) -> HTTPResponse {
        HTTPResponse(statusCode: status, url: home, body: Data("<html></html>".utf8))
    }

    @Test("R57a-R57c: one GET each, the captured URL, redirects not followed, no cookie, the JSON's models")
    func capturedRequests() async throws {
        let r57a = try RESTCapture.response(RESTCapture.categories, id: "R57a")
        let categories = await Self.run([.success(r57a)]) { client async throws(RESTBrowsingError) in
            try await client.categories()
        }
        let r57b = try RESTCapture.response(RESTCapture.lastTopics, id: "R57b")
        let lastTopics = await Self.run([.success(r57b)]) { client async throws(RESTBrowsingError) in
            try await client.lastTopics(in: 13)
        }
        let r57c = try RESTCapture.response(RESTCapture.topic, id: "R57c")
        let topic = await Self.run([.success(r57c)]) { client async throws(RESTBrowsingError) in
            try await client.topic(TopicID(category: .forum(13), topic: 28563))
        }
        #expect(try categories.result.get().source == .rest)
        #expect(try categories.result.get().value.count == 20)
        #expect(try lastTopics.result.get().source == .rest)
        #expect(try lastTopics.result.get().value.topics.count == 30)
        #expect(try topic.result.get().title == "Topic pizza maison")

        for (requests, id) in [(categories.requests, "R57a"), (lastTopics.requests, "R57b"), (topic.requests, "R57c")] {
            #expect(requests.count == 1)
            let request = try #require(requests.first)
            #expect(request.method == .get)
            #expect(request.url.absoluteString == (try Capture.meta(id)).url)
            #expect(request.redirectPolicy == .doNotFollow)
            #expect(request.headers["Cookie"] == nil)
            #expect(request.body == nil)
        }
    }

    @Test("A REST HTTP error falls back to the home page, read by ForumListParser, on the same cookie-less transport")
    func categoriesFallBack() async throws {
        let error = NetworkError.httpStatus(code: 500, url: Self.home)
        let home = try Capture.response("R01-home-anon", url: Self.home)
        let (result, requests) = await Self.run([.failure(error), .success(home)]) { client async throws(RESTBrowsingError) in
            try await client.categories()
        }
        let value = try result.get()
        #expect(value.source == .html(.network(error)))
        #expect(value.value == (try ForumListParser.parse(Capture.page("R01-home-anon")).forums))
        #expect(requests.map(\.url.absoluteString) == [(try Capture.meta("R57a")).url, (try Capture.meta("R01")).url])
        #expect(requests.allSatisfy { $0.headers["Cookie"] == nil })
    }

    @Test("Invalid JSON, or a redirect, falls back to the topic list page 1, read by TopicListParser")
    func lastTopicsFallBack() async throws {
        let list = try Capture.response("R04-list-cat13-p1-anon", url: Self.list13)
        let expected = try TopicListParser.parse(Capture.page("R04-list-cat13-p1-anon"), pageURL: Self.list13.absoluteString)

        let invalid = await Self.run([.success(Self.notJSON()), .success(list)]) { client async throws(RESTBrowsingError) in
            try await client.lastTopics(in: 13)
        }
        #expect(try invalid.result.get() == RESTBrowsingResult(value: expected, source: .html(.response(.malformedDocument))))
        #expect(invalid.requests.map(\.url.absoluteString) == [(try Capture.meta("R57b")).url, (try Capture.meta("R04")).url])

        let moved = HTTPResponse(statusCode: 302, headers: ["Location": "https://example.com/"], url: Self.home)
        let redirected = await Self.run([.success(moved), .success(list)]) { client async throws(RESTBrowsingError) in
            try await client.lastTopics(in: 13)
        }
        #expect(try redirected.result.get().source == .html(.network(.httpStatus(code: 302, url: Self.home))))
        #expect(redirected.requests.count == 2)
    }

    @Test("A failed fallback is the error of the HTML side")
    func fallbackFails() async throws {
        let maintenance = HTTPResponse(statusCode: 200, url: Self.home, body: Data("<html><body><p>Maintenance</p></body></html>".utf8))
        let page = await Self.run([.success(Self.notJSON()), .success(maintenance)]) { client async throws(RESTBrowsingError) in
            try await client.categories()
        }
        #expect(page.result.failure == .page(.maintenance("Maintenance")))

        let offline = await Self.run([.success(Self.notJSON()), .failure(.offline)]) { client async throws(RESTBrowsingError) in
            try await client.lastTopics(in: 13)
        }
        #expect(offline.result.failure == .network(.offline))
    }

    @Test("Cancellation, offline or a timeout ends the call: no HTML request", arguments: [NetworkError.cancelled, .offline, .timedOut])
    func noFallback(error: NetworkError) async {
        let (result, requests) = await Self.run([.failure(error)]) { client async throws(RESTBrowsingError) in
            try await client.categories()
        }
        #expect(result.failure == .network(error))
        #expect(requests.count == 1)
    }

    @Test("A cancelled task sends nothing")
    func cancelledBeforeSending() async {
        let transport = MockTransport(replies: [])
        let task = Task { () async throws -> RESTBrowsingResult<TopicListPage> in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await RESTBrowsingClient(transport: transport).lastTopics(in: 13)
        }
        let failure = await task.result.failure as? RESTBrowsingError
        #expect(failure == .network(.cancelled))
        #expect(await transport.requests.isEmpty)
    }

    @Test("topic(_:) has no fallback; a wrong topic is a response error")
    func topicHasNoFallback() async throws {
        let error = NetworkError.httpStatus(code: 404, url: Self.home)
        let failed = await Self.run([.failure(error)]) { client async throws(RESTBrowsingError) in
            try await client.topic(TopicID(category: .forum(13), topic: 28563))
        }
        #expect(failed.result.failure == .network(error))
        #expect(failed.requests.count == 1)

        let r57c = try RESTCapture.response(RESTCapture.topic, id: "R57c")
        let other = await Self.run([.success(r57c)]) { client async throws(RESTBrowsingError) in
            try await client.topic(TopicID(category: .forum(13), topic: 28564))
        }
        #expect(other.result.failure == .response(.invalidValue(field: "resource.id")))
    }

    @Test("Private or impossible targets are refused before any request")
    func invalidTargets() async {
        let calls: [@Sendable (RESTBrowsingClient) async throws(RESTBrowsingError) -> Void] = [
            { client async throws(RESTBrowsingError) in _ = try await client.lastTopics(in: 0) },
            { client async throws(RESTBrowsingError) in _ = try await client.topic(TopicID(category: .privateMessages, topic: 3)) },
            { client async throws(RESTBrowsingError) in _ = try await client.topic(TopicID(category: .forum(0), topic: 3)) },
            { client async throws(RESTBrowsingError) in _ = try await client.topic(TopicID(category: .forum(13), topic: 0)) }
        ]
        for call in calls {
            let (result, requests) = await Self.run([]) { client async throws(RESTBrowsingError) in try await call(client) }
            #expect(result.failure == .invalidTarget)
            #expect(requests.isEmpty)
        }
    }

    @Test("The public client sends no cookie: its transport is the cookie-less one")
    func publicClientIsAnonymous() {
        #expect(RESTBrowsingClient().transport is AnonymousTransport)
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
