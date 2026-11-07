import Foundation
import HFRNetwork
@testable import SwiftHFR
import Testing

// Port of HFRswift/Swift/AnswerView.swift (GiphyPanel :2294-2340) @ 2440d79 (GAP-089): the panel's rules, on the REST captures T40 and T41.
/// LOT-155: no request before notice N1, the entry point off without a key, the snippet, the Giphy-only media rule.
@MainActor
struct GifPickerModelTests {
    @Test func nothingIsRequestedBeforeTheNoticeIsAccepted() async throws {
        let (transport, client) = try GifTestSupport.giphy()
        let (model, _) = GifTestSupport.model(client, accepted: false)

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
        let (transport, client) = try GifTestSupport.giphy()
        let (model, settings) = GifTestSupport.model(client, accepted: false)

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

    @Test func theNoticeNamesGiphyAndItsHost() {
        let (model, _) = GifTestSupport.model(nil, accepted: false)
        #expect(model.noticeMessage.contains("le service Giphy (api.giphy.com)"))
        #expect(model.noticeMessage.contains("Seuls vos mots de recherche sont envoyés"))
    }

    @Test func anAcceptedNoticeLoadsTrendingAtOpen() async throws {
        let (transport, client) = try GifTestSupport.giphy()
        let (model, _) = GifTestSupport.model(client, accepted: true)

        await model.start()
        await model.start()

        #expect(model.phase == .loaded)
        #expect(await transport.requests.count == 1)
    }

    @Test func aBuildWithoutKeyOffersNothingAndAsksNothing() async {
        let (model, _) = GifTestSupport.model(nil, accepted: false)

        await model.start()
        await model.acceptNotice()

        #expect(!model.isAvailable)
        #expect(!model.isAskingNotice)
        #expect(model.phase == .idle)
    }

    @Test func searchSendsTheTrimmedTextAndAnEmptyFieldGoesBackToTrending() async throws {
        let (transport, client) = try GifTestSupport.giphy()
        let (model, _) = GifTestSupport.model(client, accepted: true)
        await model.start()

        model.query = "  hello "
        await model.submitSearch()
        #expect(model.activeQuery == "hello")
        #expect(model.items.map(\.id).first == GifTestSupport.firstSearchID)

        model.query = "   "
        await model.submitSearch()
        #expect(model.activeQuery == nil)

        let requests = await transport.requests
        #expect(requests.map { $0.url.path() } == ["/v1/gifs/trending", "/v1/gifs/search", "/v1/gifs/trending"])
        #expect(requests[1].url.query()?.contains("q=hello") == true)
    }

    @Test func theSnippetIsLegacysImgTagWithTheUrlAsServed() async throws {
        let (_, client) = try GifTestSupport.giphy()
        let (model, _) = GifTestSupport.model(client, accepted: true)
        await model.start()

        let gif = try #require(model.items.first)
        #expect(model.snippet(for: gif) == "[img]\(gif.originalURL.absoluteString)[/img]\n")
        #expect(gif.originalURL.host()?.hasSuffix(".giphy.com") == true)
    }

    @Test func aSnippetIsNeverMadeForAUrlOffGiphysCdn() throws {
        #expect(GifPickerModel.snippet(forOriginal: try #require(URL(string: "https://evil.example/a.gif"))) == nil)
        #expect(GifPickerModel.snippet(forOriginal: try #require(URL(string: "http://media3.giphy.com/a.gif"))) == nil)
        let own = try #require(URL(string: "https://media3.giphy.com/a.gif"))
        #expect(GifPickerModel.snippet(forOriginal: own) == "[img]https://media3.giphy.com/a.gif[/img]\n")
    }

    @Test func aGifWhoseOriginalIsOffGiphysCdnIsNeverShown() async throws {
        let (_, client) = try GifTestSupport.giphy(.init(rewriting: ("giphy.com/media", "evil.example/media")))
        let (model, _) = GifTestSupport.model(client, accepted: true)

        await model.start()

        #expect(model.phase == .loaded)
        #expect(model.items.isEmpty)
    }

    @Test func aPreviewOffGiphysCdnIsDroppedButTheGifIsKept() async throws {
        let edit: (inout [String: Any]) -> Void = { json in
            var items = json["data"] as? [[String: Any]] ?? []
            for index in items.indices {
                var images = items[index]["images"] as? [String: Any] ?? [:]
                var small = images["fixed_width_small"] as? [String: Any] ?? [:]
                small["url"] = "https://evil.example/100w.gif"
                images["fixed_width_small"] = small
                items[index]["images"] = images
            }
            json["data"] = items
        }
        let (_, client) = try GifTestSupport.giphy(.init(edit: edit))
        let (model, _) = GifTestSupport.model(client, accepted: true)

        await model.start()

        #expect(model.items.count == 3)
        for gif in model.items {
            #expect(gif.previewURL?.host() == "evil.example")
            #expect(model.previewURL(of: gif) == nil)
            #expect(model.snippet(for: gif) != nil)
        }
    }
}
