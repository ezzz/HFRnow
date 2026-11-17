import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import HFRNetwork

/// Runs `URLSessionTransport` against a loopback server: real sockets, no external network.
struct URLSessionTransportTests {
    private func makeServer(_ route: @escaping LoopbackServer.Route) throws -> LoopbackServer {
        try LoopbackServer(route: route)
    }

    private func makeTransport() -> URLSessionTransport {
        // Ignore proxy environment variables: the target is 127.0.0.1.
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        return URLSessionTransport(session: URLSession(configuration: configuration))
    }

    @Test func returnsStatusHeadersBodyAndURL() async throws {
        let server = try makeServer { _ in
            ServerReply(headers: ["Content-Type": "text/html; charset=utf-8"], body: Data("é".utf8))
        }
        defer { server.stop() }
        let response = try await makeTransport().send(.get(server.baseURL.appending(path: "a")))
        #expect(response.statusCode == 200)
        #expect(response.headers["content-type"] == "text/html; charset=utf-8")
        #expect(response.decodedText().text == "é")
        #expect(response.url.path == "/a")
    }

    @Test func sendsMethodHeadersAndEncodedBody() async throws {
        let server = try makeServer { _ in ServerReply() }
        defer { server.stop() }
        var request = HTTPRequest.post(server.baseURL.appending(path: "post"), form: FormBody([("p", "é & +")]))
        request.headers["X-Test"] = "1"
        _ = try await makeTransport().send(request)
        let seen = try #require(server.requests.first)
        #expect(seen.method == "POST")
        #expect(seen.headers["x-test"] == "1")
        #expect(seen.headers["content-type"] == FormBody.contentType)
        #expect(seen.body == Data("p=%C3%A9+%26+%2B".utf8))
    }

    @Test(arguments: [404, 500])
    func errorStatusBecomesTypedError(code: Int) async throws {
        let server = try makeServer { _ in ServerReply(status: code, body: Data("page".utf8)) }
        defer { server.stop() }
        let target = server.baseURL.appending(path: "x")
        await #expect(throws: NetworkError.httpStatus(code: code, url: target)) { try await makeTransport().send(.get(target)) }
        // The raw call still exposes the error page for callers that need it.
        let raw = try await makeTransport().perform(.get(target))
        #expect(raw.statusCode == code)
        #expect(raw.body == Data("page".utf8))
    }

    @Test func followedRedirectReportsFinalURL() async throws {
        let server = try makeServer { request in
            request.path == "/start"
                ? ServerReply(status: 301, headers: ["Location": "/hfr/final.htm"])  // relative, like HFR
                : ServerReply(body: Data("done".utf8))
        }
        defer { server.stop() }
        let response = try await makeTransport().send(.get(server.baseURL.appending(path: "start")))
        #expect(response.statusCode == 200)
        #expect(response.url.path == "/hfr/final.htm")
        #expect(response.body == Data("done".utf8))
        #expect(server.requests.map(\.path) == ["/start", "/hfr/final.htm"])
    }

    @Test func noFollowReturnsTheRedirectWithItsLocationAndNeverFetchesIt() async throws {
        let server = try makeServer { request in
            request.path == "/search"
                ? ServerReply(status: 302, headers: ["Location": "/result?x=1"])
                : ServerReply(body: Data("followed".utf8))
        }
        defer { server.stop() }
        let form = FormBody([("word", "é")])
        let response = try await makeTransport().send(
            .post(server.baseURL.appending(path: "search"), form: form, redirectPolicy: .doNotFollow)
        )
        #expect(response.statusCode == 302)
        #expect(response.redirectLocation?.path == "/result")
        #expect(response.redirectLocation?.query == "x=1")
        #expect(server.requests.map(\.path) == ["/search"])
    }

    @Test func noFollowPassesThroughAnAnswerWithoutLocation() async throws {
        let server = try makeServer { _ in ServerReply(body: Data("no result".utf8)) }
        defer { server.stop() }
        let response = try await makeTransport().send(.get(server.baseURL, redirectPolicy: .doNotFollow))
        #expect(response.statusCode == 200)
        #expect(response.redirectLocation == nil)
    }

    @Test func silentServerTimesOut() async throws {
        let server = try makeServer { _ in ServerReply(hangs: true) }
        defer { server.stop() }
        await #expect(throws: NetworkError.timedOut) { try await makeTransport().send(.get(server.baseURL, timeout: 0.5)) }
    }

    /// #683: the presets of legacy 4.0.x at `2fe43da3` (`Classes/Constants.h:70-72`, `ObjCForumSearchWorker.m:8`,
    /// `MPBackgroundService.swift:86`), all idle limits; only global search also caps the whole transfer.
    @Test func presetsAreLegacyAt2fe43da3() {
        #expect(RequestTimeout.standard == 10)
        #expect(RequestTimeout.topicSearch == 10)
        #expect(RequestTimeout.globalSearch == 10)
        #expect(RequestTimeout.globalSearchTotal == 10)
        #expect(RequestTimeout.background == 5)
        #expect(HTTPRequest.get(URL(fileURLWithPath: "/")).totalTimeout == nil)
    }

    /// #683: `timeout` is an idle limit (legacy `URLRequest.timeoutInterval`, `Classes/Constants.h:70-72` @ 2fe43da3): an answer that
    /// keeps flowing is not cut, though it takes longer than the limit.
    @Test func slowButFlowingAnswerIsNotCutByTheIdleLimit() async throws {
        let server = try makeServer { _ in
            ServerReply(body: Data(String(repeating: "x", count: 8).utf8), dripChunks: 8, dripInterval: 0.25)
        }
        defer { server.stop() }
        let response = try await makeTransport().send(.get(server.baseURL, timeout: 0.8))
        #expect(response.body.count == 8)
    }

    @Test func answerThatStallsAfterItsFirstBytesFailsAtTheIdleLimit() async throws {
        let server = try makeServer { _ in
            ServerReply(body: Data(String(repeating: "x", count: 8).utf8), dripChunks: 8, stallsAfterFirstChunk: true)
        }
        defer { server.stop() }
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: NetworkError.timedOut) { try await makeTransport().send(.get(server.baseURL, timeout: 0.6)) }
        #expect(clock.now - start < .seconds(3))
    }

    /// Global search also caps the whole transfer (legacy `timeoutIntervalForResource`, `ObjCForumSearchWorker.m:131-132`).
    @Test func totalTimeoutCutsAnAnswerThatKeepsFlowing() async throws {
        let server = try makeServer { _ in
            ServerReply(body: Data(String(repeating: "x", count: 12).utf8), dripChunks: 12, dripInterval: 0.25)
        }
        defer { server.stop() }
        let request = HTTPRequest(url: server.baseURL, timeout: 0.8, totalTimeout: 1.0)
        await #expect(throws: NetworkError.timedOut) { try await makeTransport().send(request) }
    }

    @Test func cancellingTheTaskThrowsCancelled() async throws {
        let server = try makeServer { _ in ServerReply(hangs: true) }
        defer { server.stop() }
        let transport = makeTransport()
        let url = server.baseURL
        let task = Task { try await transport.send(.get(url, timeout: 10)) }
        try await Task.sleep(for: .milliseconds(300))
        task.cancel()
        await #expect(throws: NetworkError.cancelled) { try await task.value }
    }

    @Test func refusedConnectionIsATransportError() async throws {
        let server = try makeServer { _ in ServerReply() }
        let url = server.baseURL
        server.stop()
        do {
            _ = try await makeTransport().send(.get(url))
            Issue.record("expected a failure")
        } catch {
            if case .transport = error { return }
            Issue.record("unexpected \(error)")
        }
    }

    @Test(arguments: [
        (URLError.Code.timedOut, NetworkError.timedOut),
        (.notConnectedToInternet, .offline),
        (.dataNotAllowed, .offline),
        (.cancelled, .cancelled),
        (.cannotConnectToHost, .transport(code: URLError.cannotConnectToHost.rawValue))
    ])
    func mapsURLErrors(code: URLError.Code, expected: NetworkError) {
        #expect(URLSessionTransport.map(URLError(code)) == expected)
        #expect(URLSessionTransport.map(CancellationError()) == .cancelled)
    }

    @Test func rejectsNonHTTPSchemesWithoutSending() async throws {
        let ftp = try #require(URL(string: "ftp://forum.hardware.fr/"))
        await #expect(throws: NetworkError.invalidRequest(reason: "URL scheme must be http or https")) {
            try await makeTransport().send(.get(ftp))
        }
    }

    @Test func aBodyWithinTheLimitIsReturned() async throws {
        let server = try makeServer { _ in ServerReply(body: Data(count: 1_000), omitsContentLength: true) }
        defer { server.stop() }
        var request = HTTPRequest.get(server.baseURL.appending(path: "ok"))
        request.maximumBodyBytes = 1_000
        let response = try await makeTransport().send(request)
        #expect(response.body.count == 1_000)
    }

    /// An announced size above the limit, and a streamed body that grows past it, are both refused.
    @Test(arguments: [false, true])
    func aBodyPastTheLimitIsRefused(streamed: Bool) async throws {
        let server = try makeServer { _ in ServerReply(body: Data(count: 300_000), omitsContentLength: streamed) }
        defer { server.stop() }
        var request = HTTPRequest.get(server.baseURL.appending(path: "big"))
        request.maximumBodyBytes = 100_000
        await #expect(throws: NetworkError.invalidResponse) { try await makeTransport().send(request) }
    }
}
