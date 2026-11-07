import Foundation
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Testing

// Port of HFRswift/Swift/AnswerView.swift (GiphyPanel :2294-2340) @ 2440d79 (GAP-089): the panel's rules, on the REST captures T40 and T41.
/// LOT-155: no request before notice N1, the entry point off without a key, the snippet, paging and failures. The client is the real
/// `GiphyClient` over a `MockTransport` that answers with the recorded `T40` (search) and `T41` (trending); no network, a fake key.
@MainActor
struct GifPickerModelTests {
    private static let fakeKey = "DUMMYKEY0123"
    private static let base = URL(string: "https://api.giphy.com")!

    private static func capture(_ name: String) throws -> Data {
        let captures = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appending(path: "Packages/HFRKit/Tests/HFRParsingTests/Fixtures/captures")
        return try Data(contentsOf: captures.appending(path: name))
    }

    /// Answers `/v1/gifs/search` with T40 and `/v1/gifs/trending` with T41; the requests whose index (from 0) is in `failing` go
    /// offline. `rewriting` swaps a text in both bodies (a host off Giphy's CDN).
    private static func giphy(
        rewriting host: (from: String, to: String)? = nil, failing: Set<Int> = []
    ) throws -> (MockTransport, GiphyClient) {
        func body(_ name: String) throws -> Data {
            let data = try capture(name)
            guard let host else { return data }
            return Data(String(decoding: data, as: UTF8.self).replacing(host.from, with: host.to).utf8)
        }
        let (search, trending) = (try body("T40-giphy-search.json"), try body("T41-giphy-trending.json"))
        let calls = Counter()
        let transport = MockTransport { request async throws(NetworkError) -> HTTPResponse in
            if failing.contains(calls.next()) { throw .offline }
            return HTTPResponse(statusCode: 200, url: request.url, body: request.url.path().hasSuffix("/search") ? search : trending)
        }
        let configuration = try GiphyConfiguration(baseURL: base, apiKey: fakeKey)
        return (transport, GiphyClient(configuration: configuration, transport: transport))
    }

    private static func model(
        _ client: GiphyClient?, accepted: Bool
    ) -> (GifPickerModel, InMemorySettingsStore) {
        let settings = InMemorySettingsStore(accepted ? [GifPickerModel.noticeKey: .bool(true)] : [:])
        let services = GifServices(searcher: client, hostName: "api.giphy.com", settings: settings)
        return (GifPickerModel(services: services), settings)
    }

    @Test func nothingIsRequestedBeforeTheNoticeIsAccepted() async throws {
        let (transport, client) = try Self.giphy()
        let (model, _) = Self.model(client, accepted: false)

        await model.start()
        model.query = "hello"
        await model.submitSearch()
        await model.loadMore()
        await model.retry()

        #expect(model.isAskingNotice)
        #expect(model.phase == .idle)
        #expect(await transport.requests.isEmpty)
    }

    @Test func acceptingTheNoticeIsRememberedAndLoadsTrending() async throws {
        let (transport, client) = try Self.giphy()
        let (model, settings) = Self.model(client, accepted: false)

        await model.acceptNotice()

        #expect(settings.rawValue(forKey: GifPickerModel.noticeKey) == .bool(true))
        #expect(!model.isAskingNotice)
        #expect(model.phase == .loaded)
        #expect(model.items.count == 3)
        let requests = await transport.requests
        #expect(requests.count == 1)
        #expect(requests.first?.url.path() == "/v1/gifs/trending")
        #expect(requests.first?.url.query()?.contains("rating=r") == true)
    }

    @Test func anAcceptedNoticeLoadsTrendingAtOpen() async throws {
        let (transport, client) = try Self.giphy()
        let (model, _) = Self.model(client, accepted: true)

        await model.start()
        await model.start()

        #expect(model.phase == .loaded)
        #expect(await transport.requests.count == 1)
    }

    @Test func aBuildWithoutKeyOffersNothingAndAsksNothing() async {
        let (model, _) = Self.model(nil, accepted: false)

        await model.start()
        await model.acceptNotice()

        #expect(!model.isAvailable)
        #expect(!model.isAskingNotice)
        #expect(model.phase == .idle)
    }

    @Test func searchSendsTheTrimmedTextAndAnEmptyFieldGoesBackToTrending() async throws {
        let (transport, client) = try Self.giphy()
        let (model, _) = Self.model(client, accepted: true)
        await model.start()

        model.query = "  hello "
        await model.submitSearch()
        #expect(model.activeQuery == "hello")
        #expect(model.items.map(\.id).first == "xT9IgG50Fb7Mi0prBC")

        model.query = "   "
        await model.submitSearch()
        #expect(model.activeQuery == nil)

        let paths = await transport.requests.map { $0.url.path() }
        #expect(paths == ["/v1/gifs/trending", "/v1/gifs/search", "/v1/gifs/trending"])
        #expect(await transport.requests[1].url.query()?.contains("q=hello") == true)
    }

    @Test func theSnippetIsLegacysImgTagWithTheUrlAsServed() async throws {
        let (_, client) = try Self.giphy()
        let (model, _) = Self.model(client, accepted: true)
        await model.start()

        let gif = try #require(model.items.first)
        let snippet = try #require(model.snippet(for: gif))
        #expect(snippet == "[img]\(gif.originalURL.absoluteString)[/img]\n")
        #expect(gif.originalURL.host()?.hasSuffix(".giphy.com") == true)
    }

    @Test func aGifOffGiphysCdnIsNeverShownNorPosted() async throws {
        let (_, client) = try Self.giphy(rewriting: ("giphy.com/media", "evil.example/media"))
        let (model, _) = Self.model(client, accepted: true)

        await model.start()

        #expect(model.phase == .loaded)
        #expect(model.items.isEmpty)
    }

    @Test func nextPageAsksTheNextOffsetAndKeepsNoRepeat() async throws {
        let (transport, client) = try Self.giphy()
        let (model, _) = Self.model(client, accepted: true)
        await model.start()
        let first = model.items

        await model.loadMore()

        let queries = await transport.requests.map { $0.url.query() ?? "" }
        #expect(queries.count == 2)
        #expect(queries[1].contains("offset=25"))
        // The capture answers the same three GIFs again: no repeat is added.
        #expect(model.items == first)
        #expect(!model.moreFailed)
    }

    @Test func aFailedFirstPageSaysWhyAndRetryRecovers() async throws {
        let (_, client) = try Self.giphy(failing: [0])
        let (model, _) = Self.model(client, accepted: true)

        await model.start()
        #expect(model.phase == .failed(GifPickerModel.message(for: .network(.offline))))
        #expect(model.items.isEmpty)

        await model.retry()
        #expect(model.phase == .loaded)
        #expect(model.items.count == 3)
    }

    @Test func aFailedNextPageKeepsTheListAndOffersARetry() async throws {
        let (_, client) = try Self.giphy(failing: [1])
        let (model, _) = Self.model(client, accepted: true)
        await model.start()
        let first = model.items

        await model.loadMore()
        #expect(model.moreFailed)
        #expect(model.phase == .loaded)
        #expect(model.items == first)

        await model.loadMore()
        #expect(!model.moreFailed)
    }
}

/// A thread-safe call counter: `next()` returns 0, 1, 2…
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func next() -> Int {
        lock.lock()
        defer { lock.unlock() }
        defer { count += 1 }
        return count
    }
}
