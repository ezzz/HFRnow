import Foundation
import Testing
@testable import HFRNetwork

/// LOT-098: the requests are checked as data (no network path, LESSONS 56) and the decoder runs on the captures `T40`/`T41`.
struct GiphyClientTests {
    private static let dummyKey = "DUMMYKEY0123"
    private static let base = URL(string: "https://api.giphy.com")!
    private static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Giphy
        .deletingLastPathComponent() // HFRNetworkTests
        .deletingLastPathComponent() // Tests
        .appendingPathComponent("HFRParsingTests/Fixtures/captures", isDirectory: true)

    private static func capture(_ file: String) throws -> Data { try Data(contentsOf: directory.appendingPathComponent(file)) }

    private static func client(replying reply: Result<HTTPResponse, NetworkError>) throws -> (GiphyClient, MockTransport) {
        let transport = MockTransport(replies: [reply])
        let client = GiphyClient(configuration: try GiphyConfiguration(baseURL: base, apiKey: dummyKey), transport: transport)
        return (client, transport)
    }

    private static func ok(_ body: Data) -> Result<HTTPResponse, NetworkError> {
        .success(HTTPResponse(statusCode: 200, url: base, body: body))
    }

    // MARK: Configuration

    @Test func aBlankKeyDisablesTheFeature() {
        for key in ["", "   ", "\n"] {
            #expect(throws: GiphyError.notConfigured) { try GiphyConfiguration(baseURL: Self.base, apiKey: key) }
        }
    }

    @Test func theBaseURLMustBeHTTPSOrLoopbackWithoutQueryOrUserinfo() throws {
        let refused = [
            "http://api.giphy.com", "ftp://api.giphy.com", "https://api.giphy.com?x=1",
            "https://u:p@api.giphy.com", "https://u@api.giphy.com", "https://api.giphy.com#f", "api.giphy.com"
        ]
        for text in refused {
            let url = try #require(URL(string: text))
            #expect(throws: GiphyError.invalidBaseURL, "\(text)") { try GiphyConfiguration(baseURL: url, apiKey: Self.dummyKey) }
        }
        _ = try GiphyConfiguration(baseURL: #require(URL(string: "http://127.0.0.1:8080")), apiKey: Self.dummyKey)
    }

    @Test func theDescriptionNeverShowsTheKey() throws {
        let configuration = try GiphyConfiguration(baseURL: Self.base, apiKey: Self.dummyKey)
        #expect(!"\(configuration)".contains(Self.dummyKey))
        #expect(!String(reflecting: configuration).contains(Self.dummyKey))
        var dumped = ""
        dump(GiphyClient(configuration: configuration), to: &dumped)
        #expect(!dumped.contains(Self.dummyKey), "dump and Mirror must not show the key")
    }

    // MARK: Requests (T40, T41 shapes)

    @Test func theSearchRequestIsTheCapturedOneWithRatingRAndTheKeyLast() async throws {
        let (client, transport) = try Self.client(replying: Self.ok(Self.capture("T40-giphy-search.json")))
        _ = try await client.search("hello", limit: 3)
        let request = try #require(await transport.requests.first)
        #expect(request.url.absoluteString == "https://api.giphy.com/v1/gifs/search?q=hello&limit=3&offset=0&rating=r&api_key=DUMMYKEY0123")
        #expect(request.method == .get)
        #expect(request.body == nil)
    }

    @Test func theTrendingRequestIsTheCapturedOne() async throws {
        let (client, transport) = try Self.client(replying: Self.ok(Self.capture("T41-giphy-trending.json")))
        _ = try await client.trending(limit: 3)
        let request = try #require(await transport.requests.first)
        #expect(request.url.absoluteString == "https://api.giphy.com/v1/gifs/trending?limit=3&offset=0&rating=r&api_key=DUMMYKEY0123")
    }

    @Test func theSearchTermIsTheOnlyUserDataAndIsPercentEncoded() async throws {
        let (client, transport) = try Self.client(replying: Self.ok(Self.capture("T40-giphy-search.json")))
        _ = try await client.search("  c'est la vie & +é ", limit: 3)
        let request = try #require(await transport.requests.first)
        let query = try #require(request.url.query(percentEncoded: true))
        #expect(query.hasPrefix("q=c%27est%20la%20vie%20%26%20%2B%C3%A9&limit=3"))
        #expect(!query.contains("&&") && query.split(separator: "&").count == 5, "q, limit, offset, rating, api_key and nothing else")
    }

    @Test func limitAndOffsetAreBounded() throws {
        let client = GiphyClient(configuration: try GiphyConfiguration(baseURL: Self.base, apiKey: Self.dummyKey))
        let high = try client.request(endpoint: "trending", extra: [], limit: 5000, offset: -4, rating: .parentalGuidance13)
        #expect(high.url.query?.contains("limit=50&offset=0&rating=pg-13") == true)
        let low = try client.request(endpoint: "trending", extra: [], limit: 0, offset: 10, rating: .general)
        #expect(low.url.query?.contains("limit=1&offset=10&rating=g") == true)
    }

    @Test func aBasePathIsKeptAndTrailingSlashesAreNotDoubled() async throws {
        let configuration = try GiphyConfiguration(baseURL: #require(URL(string: "https://proxy.example/giphy//")), apiKey: Self.dummyKey)
        let client = GiphyClient(configuration: configuration)
        let request = try client.request(endpoint: "search", extra: [], limit: 1, offset: 0, rating: .restricted)
        #expect(request.url.path == "/giphy/v1/gifs/search")
    }

    // MARK: Policy: injected host only, no cookie, no redirect

    @Test func theRequestPolicyKeepsTheKeyOnTheInjectedHost() throws {
        let client = GiphyClient(configuration: try GiphyConfiguration(baseURL: Self.base, apiKey: Self.dummyKey))
        let request = try client.request(endpoint: "search", extra: [("q", "x")], limit: 3, offset: 0, rating: .restricted)
        #expect(request.url.host == "api.giphy.com")
        #expect(request.url.scheme == "https")
        #expect(request.redirectPolicy == .doNotFollow, "a redirect would replay the key on another host")
        #expect(request.headers["Cookie"] == nil)
        #expect(request.headers["Referer"] == nil)
        #expect(request.headers["Authorization"] == nil)
        #expect(request.maximumBodyBytes == GiphyClient.maximumResponseBytes)
        #expect(request.timeout == GiphyClient.timeout)
    }

    @Test func theDefaultTransportIsTheCookielessOne() throws {
        // The default argument is observable through `Mirror`: the stored transport must be an `AnonymousTransport`.
        let client = GiphyClient(configuration: try GiphyConfiguration(baseURL: Self.base, apiKey: Self.dummyKey))
        let transport = Mirror(reflecting: client).children.first { $0.label == "transport" }?.value
        #expect(transport is AnonymousTransport)
    }

    @Test func aRedirectIsAnHTTPErrorNotAFollowedHop() async throws {
        let moved = HTTPResponse(statusCode: 302, headers: ["Location": "https://elsewhere.example/x"], url: Self.base)
        let (client, transport) = try Self.client(replying: .success(moved))
        await #expect(throws: GiphyError.http(statusCode: 302)) { try await client.trending() }
        #expect(await transport.requests.count == 1)
    }

    // MARK: Decoding on the captures

    @Test func theSearchCaptureDecodesToThreeGIFsWithTheirOriginalURLs() async throws {
        let (client, _) = try Self.client(replying: Self.ok(Self.capture("T40-giphy-search.json")))
        let page = try await client.search("hello", limit: 3)
        #expect(page.items.count == 3)
        #expect(page.totalCount == 500)
        #expect(page.offset == 0)
        let first = try #require(page.items.first)
        #expect(first.id == "xT9IgG50Fb7Mi0prBC")
        #expect(first.title == "Tom Hanks Hello GIF")
        #expect(first.rating == "g")
        #expect(first.originalWidth == 400)
        #expect(first.originalHeight == 200)
        #expect(first.originalURL.host == "media2.giphy.com")
        #expect(first.originalURL.path == "/media/xT9IgG50Fb7Mi0prBC/giphy.gif")
        #expect(first.originalURL.query?.contains("ep=v1_gifs_search") == true)
        #expect(first.previewURL?.path == "/media/xT9IgG50Fb7Mi0prBC/100w.gif")
        #expect(page.items.map(\.id) == ["xT9IgG50Fb7Mi0prBC", "CK0Eg2ymtfzTO2yVJD", "dzaUX7CAG0Ihi"])
    }

    @Test func theTrendingCaptureDecodes() async throws {
        let (client, _) = try Self.client(replying: Self.ok(Self.capture("T41-giphy-trending.json")))
        let page = try await client.trending(limit: 3)
        #expect(page.items.map(\.id) == ["uCrWfLLVUxSj9NXjgp", "1ojn1S7BTXUry8elNi", "xT4Aphm45GMfpVEUxO"])
        #expect(page.totalCount == 170)
        #expect(page.items.allSatisfy { $0.originalURL.scheme == "https" && $0.previewURL != nil })
    }

    @Test func thePostableURLDropsTheQueryAndTheOriginalKeepsIt() async throws {
        let (client, _) = try Self.client(replying: Self.ok(Self.capture("T40-giphy-search.json")))
        let first = try #require(try await client.search("hello").items.first)
        #expect(first.originalURLWithoutTracking.absoluteString == "https://media2.giphy.com/media/xT9IgG50Fb7Mi0prBC/giphy.gif")
        #expect(first.originalURL.query != nil)
    }

    // MARK: Errors

    @Test func anEmptySearchSendsNothing() async throws {
        let (client, transport) = try Self.client(replying: Self.ok(Data()))
        await #expect(throws: GiphyError.emptyQuery) { try await client.search("  \n ") }
        #expect(await transport.requests.isEmpty)
    }

    @Test func aNonSuccessStatusIsAnHTTPErrorWithoutTheBody() async throws {
        let (client, _) = try Self.client(replying: .success(HTTPResponse(statusCode: 429, url: Self.base, body: Data("slow down".utf8))))
        await #expect(throws: GiphyError.http(statusCode: 429)) { try await client.search("a") }
    }

    @Test(arguments: ["", "[]", "not json", #"{"data":{}}"#, #"{"meta":{}}"#, #"{"data":"x"}"#])
    func anAnswerWithoutADataArrayIsInvalid(body: String) async throws {
        let (client, _) = try Self.client(replying: Self.ok(Data(body.utf8)))
        await #expect(throws: GiphyError.invalidResponse) { try await client.trending() }
    }

    @Test func anItemWithoutIDOrOriginalHTTPSURLIsDroppedAndTheRestKept() async throws {
        let json = """
        {"data":[
          {"id":"a","images":{"original":{"url":"https://media.giphy.com/a.gif","width":"10","height":"x"}}},
          {"id":"","images":{"original":{"url":"https://media.giphy.com/b.gif"}}},
          {"id":"c","images":{"original":{"url":"javascript:alert(1)"}}},
          {"id":"d","images":{"original":{"url":"http://media.giphy.com/d.gif"}}},
          {"id":"e","images":{}},
          {"id":"f"},
          7
        ],"pagination":{"total_count":"many"}}
        """
        let (client, _) = try Self.client(replying: Self.ok(Data(json.utf8)))
        let page = try await client.trending()
        #expect(page.items.map(\.id) == ["a"])
        #expect(page.items.first?.originalWidth == 10)
        #expect(page.items.first?.originalHeight == nil)
        #expect(page.items.first?.previewURL == nil)
        #expect(page.totalCount == nil, "a pagination block of another shape is ignored, not fatal")
    }

    @Test(arguments: [NetworkError.offline, .timedOut, .cancelled, .invalidResponse, .transport(code: -1)])
    func transportFailuresAreWrapped(error: NetworkError) async throws {
        let (client, _) = try Self.client(replying: .failure(error))
        await #expect(throws: GiphyError.network(error)) { try await client.trending() }
    }

    @Test func aStatusErrorFromTheTransportLosesTheQueryThatHoldsTheKey() async throws {
        let url = try #require(URL(string: "https://api.giphy.com/v1/gifs/search?q=x&api_key=\(Self.dummyKey)"))
        let (client, _) = try Self.client(replying: .failure(.httpStatus(code: 403, url: url)))
        do {
            _ = try await client.search("x")
            Issue.record("expected a failure")
        } catch {
            #expect(!"\(error)".contains(Self.dummyKey))
            #expect(error == .network(.httpStatus(code: 403, url: URL(string: "https://api.giphy.com/v1/gifs/search")!)))
        }
    }

    @Test func aRefusedRequestReasonIsReplacedByFixedText() async throws {
        let (client, _) = try Self.client(replying: .failure(.invalidRequest(reason: "bad \(Self.dummyKey)")))
        do {
            _ = try await client.trending()
            Issue.record("expected a failure")
        } catch {
            #expect(!"\(error)".contains(Self.dummyKey))
        }
    }
}
