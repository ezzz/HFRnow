import Foundation
import HFRNetwork
@testable import SwiftHFR
import Testing

private struct OpenedViewer {
    let images: [GalleryImage]
    let index: Int
    let token: Int
}

/// The `image` message of `reader.js` (LOT-109): decoded into a typed case, then filtered by policy C in the controller.
@MainActor
struct ReaderImageViewerBridgeTests: ReaderWebTesting {
    private func decode(_ body: Any) -> Result<ReaderBridgeMessage.Decoded, ReaderBridgeMessage.Failure> {
        do throws(ReaderBridgeMessage.Failure) { return .success(try ReaderBridgeMessage.decode(body)) } catch { return .failure(error) }
    }

    @Test func anImageMessageDecodes() {
        #expect(decode(["type": "image", "token": 3, "urls": ["a", "b"] as [Any], "index": 1])
            == .success(.init(token: 3, message: .image(urls: ["a", "b"], index: 1))))
    }

    @Test func aBadImageMessageIsRejectedWhole() {
        let base: [String: Any] = ["type": "image", "token": 1]
        #expect(decode(base) == .failure(.invalidPayload))
        #expect(decode(base.merging(["urls": ["a"] as [Any], "index": 1]) { $1 }) == .failure(.invalidPayload))
        #expect(decode(base.merging(["urls": ["a"] as [Any], "index": -1]) { $1 }) == .failure(.invalidPayload))
        #expect(decode(base.merging(["urls": ["a"] as [Any], "index": "0"]) { $1 }) == .failure(.invalidPayload))
        #expect(decode(base.merging(["urls": ["a"] as [Any], "index": true]) { $1 }) == .failure(.invalidPayload))
        #expect(decode(base.merging(["urls": "a", "index": 0]) { $1 }) == .failure(.invalidPayload))
        #expect(decode(base.merging(["urls": [] as [Any], "index": 0]) { $1 }) == .failure(.invalidPayload))
        // An entry that is not a string must not shift the index onto another picture.
        #expect(decode(base.merging(["urls": ["a", 5, "c"] as [Any], "index": 2]) { $1 }) == .failure(.invalidPayload))
    }

    @Test func theListIsBounded() {
        let urls = Array(repeating: "https://forum-images.hardware.fr/images/a.png", count: ReaderBridgeMessage.maximumImages + 1)
        #expect(decode(["type": "image", "token": 1, "urls": urls as [Any], "index": 0]) == .failure(.invalidPayload))
    }

    @Test func theControllerOpensTheViewerOnlyOnAllowedPictures() {
        let (controller, _) = makeController(transport: imageTransport())
        var opened: [OpenedViewer] = []
        controller.events.image = { opened.append(OpenedViewer(images: $0, index: $1, token: $2)) }
        let shown = document(token: 4)
        let thirdParty = ["https://i.imgur.com/a.jpg", "https://i.imgur.com/b.jpg"]

        // Neither picture was allowed: nothing opens.
        _ = controller.handle(.image(urls: thirdParty, index: 0), in: shown)
        #expect(opened.isEmpty)

        // The user allowed the first one by tapping its placeholder; the neighbour stays out.
        _ = controller.handle(.tap(url: thirdParty[0]), in: shown)
        _ = controller.handle(.image(urls: thirdParty, index: 0), in: shown)
        #expect(opened.count == 1)
        #expect(opened.first?.images.map(\.shown.absoluteString) == [thirdParty[0]])
        #expect(opened.first?.token == 4)

        // A blocked address never opens (the gallery filter itself is covered by `ImageGalleryTests`).
        _ = controller.handle(.tap(url: "http://192.168.1.1/a.png"), in: shown)
        _ = controller.handle(.image(urls: ["http://192.168.1.1/a.png"], index: 0), in: shown)
        #expect(opened.count == 1)
    }

    @Test func theViewerRequestsCarryTheHostRefererAndNoCookie() async throws {
        let transport = MockTransport { request in
            HTTPResponse(statusCode: 200, headers: ["Content-Type": "image/png"], url: request.url, body: Data([1]))
        }
        let fetcher = ReaderImageFetcher(transport: transport)
        _ = try await fetcher.image(at: URL(string: "https://reho.st/self/a.jpg")!, allowsThirdParty: true, hostTable: .standard)
        _ = try await fetcher.image(at: URL(string: "https://i.imgur.com/a.jpg")!, allowsThirdParty: true, hostTable: .standard)
        _ = try await fetcher.image(at: URL(string: "https://reho.st/self/b.jpg")!, allowsThirdParty: true)
        let requests = await transport.requests
        #expect(requests.map { $0.headers["Referer"] } == ["https://forum.hardware.fr/", nil, nil])
        #expect(requests.allSatisfy { $0.redirectPolicy == .doNotFollow })
        let names = requests.flatMap { $0.headers.fields.keys }.map { $0.trimmingCharacters(in: .whitespaces).lowercased() }
        #expect(!names.contains("cookie"))
    }

    @Test func aRefererNeverTravelsToTheNextHost() async throws {
        let transport = MockTransport { request in
            if request.url.host() == "reho.st" {
                return HTTPResponse(statusCode: 302, headers: ["Location": "https://cdn.example.org/a.jpg"], url: request.url)
            }
            return HTTPResponse(statusCode: 200, headers: ["Content-Type": "image/jpeg"], url: request.url, body: Data([1]))
        }
        let fetcher = ReaderImageFetcher(transport: transport)
        _ = try await fetcher.image(at: URL(string: "https://reho.st/self/a.jpg")!, allowsThirdParty: true, hostTable: .standard)
        let requests = await transport.requests
        #expect(requests.map { $0.headers["Referer"] } == ["https://forum.hardware.fr/", nil])
    }

    /// `reader.js` in a real web view: which pictures a tap lists, and which taps open nothing.
    @Test func aTapInThePageListsTheLoadedPicturesAndSkipsSmileysAndClosedSpoilers() async throws {
        let content = """
            <p><img class="hfrplusimg" src="https://forum-images.hardware.fr/images/a.png" alt="a"></p>
            <p><img src="https://forum-images.hardware.fr/icones/smile.gif" alt=":)"></p>
            <p><img class="hfrplusimg" src="https://forum-images.hardware.fr/images/b.png" alt="b"></p>
            <table class="spoiler"><tr><td><b class="s1Topic">Spoiler :</b><br><div class="Topic masque">
            <img class="hfrplusimg" src="https://forum-images.hardware.fr/images/hidden.png" alt="h"></div></td></tr></table>
            """
        let (controller, recorder) = makeController(transport: imageTransport())
        var opened: [OpenedViewer] = []
        controller.events.image = { opened.append(OpenedViewer(images: $0, index: $1, token: $2)) }
        controller.show(document(token: 1, content: content))
        #expect(await until { recorder.ready == [1] })
        #expect(await settled(controller))

        let pictures = "document.querySelectorAll('img.hfrplusimg')"
        // The original address is kept for the viewer, the attribute holds the proxied one.
        let kept = try await evaluate("return Array.from(\(pictures)).map(i => i.dataset.viewerSrc);", in: controller) as? [String]
        #expect(kept == [
            "https://forum-images.hardware.fr/images/a.png", "https://forum-images.hardware.fr/images/b.png",
            "https://forum-images.hardware.fr/images/hidden.png"
        ])
        _ = try await evaluate("\(pictures)[1].click(); return true;", in: controller)
        #expect(await until { opened.count == 1 })
        #expect(opened.first?.images.map(\.shown.lastPathComponent) == ["a.png", "b.png"])
        #expect(opened.first?.index == 1)

        _ = try await evaluate("document.querySelector('img:not(.hfrplusimg):not(.avatar)').click(); return true;", in: controller)
        _ = try await evaluate("document.querySelector('img.avatar')?.click(); return true;", in: controller)
        // A later tap that must be heard proves the earlier ones were not queued behind it.
        _ = try await evaluate("document.querySelector('table.spoiler td').click(); \(pictures)[2].click(); return true;", in: controller)
        #expect(await until { opened.count == 2 })
        #expect(opened.last?.images.map(\.shown.lastPathComponent) == ["a.png", "b.png", "hidden.png"])
        #expect(opened.last?.index == 2)
    }
}
