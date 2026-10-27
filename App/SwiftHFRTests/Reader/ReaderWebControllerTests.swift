import Foundation
import HFRModels
import HFRNetwork
@testable import SwiftHFR
import Testing
import WebKit

/// The real web view, driven end to end: what the page may run, request and navigate to.
@MainActor
struct ReaderWebControllerTests {
    nonisolated private static let pixel = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
    ) ?? Data()

    /// Content that a broken sanitizer could let through: page scripts and handlers must stay inert anyway.
    private static let hostileContent = """
        <p>Bonjour <img src="https://forum-images.hardware.fr/icones/smile.gif" alt=":)"></p>
        <script>document.title = "script ran";</script>
        <img src="https://forum-images.hardware.fr/icones/none.gif" onerror="document.title = 'handler ran'">
        <p><img class="hfrplusimg" src="https://i.imgur.com/photo.jpg" alt="photo"></p>
        <p><img class="hfrplusimg" src="http://192.168.1.1/admin.png" alt="lan"></p>
        <p><a href="https://example.com/page">un lien</a></p>
        <iframe src="https://example.com/frame"></iframe>
        <table class="spoiler"><tr><td><b class="s1Topic">Spoiler :</b><br><div class="Topic masque"><p>secret</p></div></td></tr></table>
        """

    private final class Recorder {
        var ready: [Int] = []
        var links: [URL] = []
    }

    private func makeController(transport: MockTransport, autoLoad: Bool = false) -> (ReaderWebController, Recorder) {
        let controller = ReaderWebController(
            imageFetcher: ReaderImageFetcher(transport: transport), autoLoadsThirdPartyImages: { autoLoad }
        )
        let recorder = Recorder()
        controller.events = ReaderWebController.Events(
            ready: { recorder.ready.append($0) }, link: { recorder.links.append($0) }, video: { _, _, _ in }
        )
        return (controller, recorder)
    }

    private func document(token: Int, content: String = hostileContent) -> ReaderDocument {
        let message = ReaderMessage(
            numreponse: 7, author: "auteur", isDeleted: false, isContinuation: false,
            avatarURL: URL(string: "https://forum-images.hardware.fr/avatars/a.png"), dateText: "27-10-2026 10:00:00",
            editNote: nil, quotedByCount: nil, content: MessageContent(html: content)
        )
        let page = ReaderPage(topicID: readerTopic, title: "Titre", currentPage: 1, maxPage: 1, messages: [message])
        return ReaderDocument(
            token: token, html: TopicHTMLBuilder.document(for: page, token: token), anchor: nil, keepsScrollPosition: false
        )
    }

    private func until(_ condition: () -> Bool, timeout: Duration = .seconds(20)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            if clock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    private func until(async condition: () async -> Bool, timeout: Duration = .seconds(20)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while await !condition() {
            if clock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    private func evaluate(_ script: String, in controller: ReaderWebController) async throws -> Any? {
        try await controller.webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: ReaderWebController.world)
    }

    private func imageTransport() -> MockTransport {
        MockTransport { request in
            HTTPResponse(statusCode: 200, headers: ["Content-Type": "image/png"], url: request.url, body: Self.pixel)
        }
    }

    @Test func thePageRunsNoScriptAndRoutesEveryImageThroughThePolicy() async throws {
        let transport = imageTransport()
        let (controller, recorder) = makeController(transport: transport)
        controller.show(document(token: 1))
        #expect(await until { recorder.ready == [1] })
        // Images settle after DOMContentLoaded.
        #expect(await until { controller.imageRequests.count >= 3 })
        try await Task.sleep(for: .milliseconds(300))

        let title = try await evaluate("return document.title;", in: controller) as? String
        #expect(title == "Titre")
        let requested = Set(await transport.requests.map(\.url.absoluteString))
        #expect(requested == [
            "https://forum-images.hardware.fr/icones/smile.gif", "https://forum-images.hardware.fr/icones/none.gif",
            "https://forum-images.hardware.fr/avatars/a.png"
        ])
        #expect(controller.imageRequests.allSatisfy { $0.allowed })
        let placeholders = try await evaluate("return document.querySelectorAll('button.image-tap').length;", in: controller)
        #expect((placeholders as? NSNumber)?.intValue == 1)
        let blocked = try await evaluate(
            "return Array.from(document.querySelectorAll('.image-link')).map(e => e.textContent);", in: controller
        ) as? [String]
        #expect(blocked == ["http://192.168.1.1/admin.png"])
        let frames = try await evaluate("return document.querySelectorAll('iframe').length;", in: controller)
        #expect((frames as? NSNumber)?.intValue == 1) // present in the markup, refused by frame-src and navigation
        #expect(controller.webView.url == ReaderWebController.pageURL(token: 1))
    }

    @Test func theStylesheetLoadsAndASpoilerOpensOnTap() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.show(document(token: 1))
        #expect(await until { recorder.ready == [1] })
        let visibility = "return getComputedStyle(document.querySelector('div.masque')).visibility;"
        #expect(await until(async: { (try? await self.evaluate(visibility, in: controller) as? String) == "hidden" }))
        _ = try await evaluate("document.querySelector('table.spoiler td').click(); return true;", in: controller)
        #expect(try await evaluate(visibility, in: controller) as? String == "visible")
    }

    @Test func aTapLoadsAThirdPartyImageThroughTheCookielessClient() async throws {
        let transport = imageTransport()
        let (controller, recorder) = makeController(transport: transport)
        controller.show(document(token: 1))
        #expect(await until { recorder.ready == [1] })
        #expect(await transport.requests.contains { $0.url.host() == "i.imgur.com" } == false)
        _ = try await evaluate("document.querySelector('button.image-tap').click(); return true;", in: controller)
        #expect(await until { controller.imageRequests.contains { $0.requested.host() == "i.imgur.com" && $0.allowed } })
        var fetched = false
        for _ in 0..<100 where !fetched {
            fetched = await transport.requests.contains { $0.url.absoluteString == "https://i.imgur.com/photo.jpg" }
            if !fetched { try await Task.sleep(for: .milliseconds(20)) }
        }
        #expect(fetched)
        #expect(await transport.requests.allSatisfy { $0.headers["Cookie"] == nil && $0.headers["Referer"] == nil })
    }

    @Test func theImageModeLoadsThirdPartyImagesWithoutATap() async throws {
        let transport = imageTransport()
        let (controller, recorder) = makeController(transport: transport, autoLoad: true)
        controller.show(document(token: 1))
        #expect(await until { recorder.ready == [1] })
        #expect(await until { controller.imageRequests.contains { $0.requested.host() == "i.imgur.com" } })
        #expect(!controller.imageRequests.contains { $0.requested.host() == "192.168.1.1" })
    }

    @Test func aTappedLinkLeavesTheReaderToTheApp() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.show(document(token: 1))
        #expect(await until { recorder.ready == [1] })
        _ = try await evaluate("document.querySelector('a[href=\"https://example.com/page\"]').click(); return true;", in: controller)
        #expect(await until { recorder.links == [URL(string: "https://example.com/page")] })
        #expect(controller.webView.url == ReaderWebController.pageURL(token: 1))
    }

    @Test func onlyTheLatestDocumentReportsReady() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.show(document(token: 1))
        controller.show(document(token: 2, content: "<p>deux</p>"))
        #expect(await until { recorder.ready.contains(2) })
        try await Task.sleep(for: .milliseconds(300))
        #expect(recorder.ready == [2])
        let text = try await evaluate("return document.querySelector('.content').textContent;", in: controller) as? String
        #expect(text == "deux")
    }
}
