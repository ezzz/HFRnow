import HFRModels
import HFRNetwork
@testable import SwiftHFR
import Testing
import UIKit
import WebKit

/// Issue #750: SwiftUI sends `onDisappear` to a reader pushed again in a collapsed split view, before its web view is in a
/// window, and never `onAppear` again. The web view's window decides whether the reader is on screen.
@MainActor
@Suite(.serialized)
struct ReaderPresenceWebTests: ReaderWebTesting {
    /// The reopen of #750 as measured: the document is handed, the load is stopped while the web view is on its way in, then
    /// the web view enters its window. The page must load (before the fix: "show skipped: stopped" forever).
    @Test func aReaderStoppedOnItsWayInLoadsOnceItsWebViewIsInAWindow() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        let window = try #require(recorder.window)
        controller.webView.removeFromSuperview()
        controller.show(document(token: 1))
        controller.stopLoading()
        #expect(await until({ !recorder.ready.isEmpty }, timeout: .seconds(2)) == false, "ready before the window")
        window.addSubview(controller.webView)
        #expect(await until({ recorder.ready == [1] }, timeout: .seconds(120)), "ready: \(recorder.ready)")
    }

    /// The same sequence through the lifecycle calls: the disappearance out of a window leaves, the window brings it back.
    @Test func aDisappearanceBeforeTheWindowLeavesAndTheWindowBringsTheReaderBack() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        let window = try #require(recorder.window)
        var left = 0
        var returned = 0
        controller.events.left = { left += 1; controller.stopLoading() }
        controller.events.returned = { returned += 1 }
        controller.webView.removeFromSuperview()
        controller.viewAppeared()
        controller.show(document(token: 1))
        controller.viewDisappeared()
        #expect(left == 1)
        window.addSubview(controller.webView)
        #expect(returned == 1)
        #expect(await until({ recorder.ready == [1] }, timeout: .seconds(120)), "ready: \(recorder.ready)")
    }

    /// A disappearance while the web view is in a window changes nothing; its leaving the window then is the real leave.
    @Test func aDisappearanceInAWindowWaitsForTheWebViewToLeaveIt() throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        _ = try #require(recorder.window)
        var left = 0
        controller.events.left = { left += 1; controller.stopLoading() }
        controller.viewAppeared()
        controller.show(document(token: 1))
        controller.viewDisappeared()
        #expect(left == 0)
        controller.webView.removeFromSuperview()
        #expect(left == 1)
    }

    /// A real leave (the web view leaves its window first, then `onDisappear`) leaves once; a window change of a reader on
    /// screen (no stop) brings nothing back.
    @Test func aRealLeaveLeavesOnceAndAnAppearedReaderIsNotBroughtBack() throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        let window = try #require(recorder.window)
        var left = 0
        var returned = 0
        controller.events.left = { left += 1; controller.stopLoading() }
        controller.events.returned = { returned += 1 }
        controller.viewAppeared()
        controller.webView.removeFromSuperview()
        window.addSubview(controller.webView)
        #expect(left == 0)
        #expect(returned == 0)
        controller.webView.removeFromSuperview()
        controller.viewDisappeared()
        #expect(left == 1)
    }

    /// A page whose one message holds one posted picture of the forum's own host.
    private static let picture = "https://forum-images.hardware.fr/images/perso/photo.png"

    private func pictureDocument() -> ReaderDocument {
        let message = ReaderMessage(
            numreponse: 7, author: "auteur", isDeleted: false, isContinuation: false, avatarURL: nil, dateText: "",
            editNote: nil, quotedByCount: nil,
            content: MessageContent(html: "<p><img class=\"hfrplusimg\" src=\"\(Self.picture)\" alt=\"\"></p>")
        )
        let page = ReaderPage(topicID: readerTopic, title: "Titre", currentPage: 1, maxPage: 1, messages: [message])
        return ReaderDocument(token: 1, html: TopicHTMLBuilder.document(for: page, token: 1), anchor: nil, keepsScrollPosition: false)
    }

    /// The page's picture is loaded and nothing is a link.
    private let loaded = """
        const images = Array.from(document.querySelectorAll("img"));
        return images.length === 1 && images.every((img) => img.complete && img.naturalWidth > 0)
            && document.querySelector(".image-link") === null;
        """

    /// #1187: images still loading when a shown page is stopped (a tab switch) are cut; when the reader comes back they load,
    /// instead of staying blank or turning into links until « Actualiser ». The page is not loaded again: it keeps its place.
    @Test func aShownPageStoppedWithImagesInFlightShowsThemWhenItComesBack() async throws {
        let gate = ReaderGate()
        let calls = ReaderCallCounter()
        let transport = MockTransport { request in
            // The first image is held until the page has been stopped and has come back.
            if calls.next() == 1 { await gate.wait() }
            return HTTPResponse(statusCode: 200, headers: ["Content-Type": "image/png"], url: request.url, body: readerTestPixel)
        }
        let (controller, recorder) = makeController(transport: transport)
        let shown = pictureDocument()
        controller.show(shown)
        #expect(await until { recorder.ready == [1] })
        #expect(await until(async: { await transport.requests.count >= 1 }), "the image never left")
        controller.stopLoading()
        controller.resume()
        controller.show(shown)
        await gate.open()
        #expect(
            await until(async: { (try? await self.evaluate(self.loaded, in: controller)) as? Bool == true }),
            "the cut image is still blank or a link"
        )
        #expect(recorder.ready == [1], "the page was loaded again")
    }

    /// The other way WebKit may end a cut load: the picture failed into a link. Asked again, it is put back where it was and
    /// fetched again.
    @Test func aCutPictureThatFailedIntoALinkIsPutBackAndFetchedAgain() async throws {
        let calls = ReaderCallCounter()
        let transport = MockTransport { request in
            // The first answer fails, so the page turns the picture into a link; the next one serves it.
            if calls.next() == 1 { return HTTPResponse(statusCode: 404, url: request.url) }
            return HTTPResponse(statusCode: 200, headers: ["Content-Type": "image/png"], url: request.url, body: readerTestPixel)
        }
        let (controller, recorder) = makeController(transport: transport)
        controller.show(pictureDocument())
        #expect(await until { recorder.ready == [1] })
        let failed = """
            return document.querySelector("img") === null && document.querySelector(".image-link") !== null;
            """
        #expect(await until(async: { (try? await self.evaluate(failed, in: controller)) as? Bool == true }), "no link")
        let before = await transport.requests.count
        let retried = try await evaluate("return window.hfrReader.retryImages([\"\(Self.picture)\"]);", in: controller)
        #expect(retried as? Bool == true)
        #expect(await until(async: { (try? await self.evaluate(self.loaded, in: controller)) as? Bool == true }))
        #expect(await transport.requests.count > before, "the picture was not fetched again")
    }
}
