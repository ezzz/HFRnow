import Foundation
import Testing
@testable import HFRNetwork

struct MockTransportTests {
    let url = URL(string: "https://forum.hardware.fr/forum1.php")!

    @Test func repliesInOrderRecordsRequestsThenRunsOut() async throws {
        let first = HTTPResponse(statusCode: 200, url: url, body: Data("a".utf8))
        let second = HTTPResponse(statusCode: 200, url: url, body: Data("b".utf8))
        let mock = MockTransport(replies: [.success(first), .success(second)])

        #expect(try await mock.send(.get(url)).body == Data("a".utf8))
        #expect(try await mock.send(.get(url)).body == Data("b".utf8))
        await #expect(throws: NetworkError.unscripted) { try await mock.send(.get(url)) }
        #expect(await mock.requests.count == 3)
        #expect(await mock.requests.first?.url == url)
    }

    @Test func handlerSeesTheRequest() async throws {
        let mock = MockTransport { request throws(NetworkError) in
            HTTPResponse(statusCode: 200, url: request.url, body: request.body ?? Data())
        }
        let post = HTTPRequest.post(url, form: FormBody([("q", "é")]))
        #expect(try await mock.send(post).body == Data("q=%C3%A9".utf8))
    }

    @Test(arguments: [400, 403, 404, 500, 503])
    func sendMapsErrorStatusesToHTTPStatus(code: Int) async {
        let mock = MockTransport(replies: [.success(HTTPResponse(statusCode: code, url: url, body: Data("page".utf8)))])
        await #expect(throws: NetworkError.httpStatus(code: code, url: url)) { try await mock.send(.get(url)) }
    }

    @Test(arguments: [200, 204, 301, 302, 399])
    func sendReturnsNonErrorStatuses(code: Int) async throws {
        let mock = MockTransport(replies: [.success(HTTPResponse(statusCode: code, url: url))])
        #expect(try await mock.send(.get(url)).statusCode == code)
    }

    @Test func performReturnsErrorStatusBodyUntouched() async throws {
        let mock = MockTransport(replies: [.success(HTTPResponse(statusCode: 404, url: url, body: Data("gone".utf8)))])
        let response = try await mock.perform(.get(url))
        #expect(response.statusCode == 404)
        #expect(response.body == Data("gone".utf8))
    }

    @Test func scriptedFailureIsThrownAsIs() async {
        let mock = MockTransport(replies: [.failure(.timedOut)])
        await #expect(throws: NetworkError.timedOut) { try await mock.send(.get(url)) }
    }

    @Test func redirectLocationResolvesRelativeAgainstResponseURL() {
        let response = HTTPResponse(
            statusCode: 301, headers: ["location": "/hfr/Discussions/sujet_1711_450.htm"], url: url
        )
        #expect(response.isRedirect)
        #expect(response.redirectLocation?.absoluteString == "https://forum.hardware.fr/hfr/Discussions/sujet_1711_450.htm")
    }

    @Test func missingLocationIsNil() {
        #expect(HTTPResponse(statusCode: 302, url: url).redirectLocation == nil)
        #expect(!HTTPResponse(statusCode: 200, url: url).isRedirect)
    }

    @Test func headersAreCaseInsensitive() {
        var headers: HTTPHeaders = ["Content-Type": "a"]
        #expect(headers["content-type"] == "a")
        headers["CONTENT-TYPE"] = "b"
        #expect(headers.fields == ["content-type": "b"])
        headers["content-type"] = nil
        #expect(headers.fields.isEmpty)
    }
}
