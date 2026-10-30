import Foundation
import HFRModels
import HFRNetwork
@testable import SwiftHFR
import UIKit
import WebKit

/// A 1×1 PNG served for every allowed image.
let readerTestPixel = Data(
    base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
) ?? Data()

/// Content that a broken sanitizer could let through: page scripts and handlers must stay inert anyway.
let readerHostileContent = """
        <p>Bonjour <img src="https://forum-images.hardware.fr/icones/smile.gif" alt=":)"></p>
        <script>document.title = "script ran";</script>
        <img src="https://forum-images.hardware.fr/icones/none.gif" onerror="document.title = 'handler ran'">
        <p><img class="hfrplusimg" src="https://i.imgur.com/photo.jpg" alt="photo"></p>
        <p><img class="hfrplusimg" src="http://192.168.1.1/admin.png" alt="lan"></p>
        <p><a href="https://example.com/page">un lien</a></p>
        <iframe src="https://example.com/frame"></iframe>
        <table class="spoiler"><tr><td><b class="s1Topic">Spoiler :</b><br><div class="Topic masque"><p>secret</p></div></td></tr></table>
        """

/// What the controller reported to the screen, and the window hosting its web view.
final class ReaderWebRecorder {
    var ready: [Int] = []
    var links: [URL] = []
    /// Hosts the web view in a window, as on screen (keeps WebKit from treating it as hidden and throttling it).
    var window: UIWindow?
}

/// Drives a real `ReaderWebController` in tests: build it, show a document, wait, read the DOM from the reader's world.
@MainActor
protocol ReaderWebTesting {}

extension ReaderWebTesting {
    func makeController(transport: MockTransport, autoLoad: Bool = false) -> (ReaderWebController, ReaderWebRecorder) {
        let controller = ReaderWebController(
            imageFetcher: ReaderImageFetcher(transport: transport), autoLoadsThirdPartyImages: { autoLoad }
        )
        let recorder = ReaderWebRecorder()
        controller.events = ReaderWebController.Events(
            ready: { recorder.ready.append($0) }, link: { recorder.links.append($0) }, video: { _, _, _ in }
        )
        if let scene = UIApplication.shared.connectedScenes.first(where: { $0 is UIWindowScene }) as? UIWindowScene {
            let window = UIWindow(windowScene: scene)
            window.frame = CGRect(x: 0, y: 0, width: 400, height: 800)
            controller.webView.frame = window.bounds
            window.addSubview(controller.webView)
            window.isHidden = false
            recorder.window = window
        }
        return (controller, recorder)
    }

    func document(token: Int, content: String = readerHostileContent) -> ReaderDocument {
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

    /// Polls `condition` until it holds or `timeout` passes. The deadline counts from the call, and the first web test of
    /// a suite starts while the rest of the app suite runs in parallel: on the CI simulator that start alone has taken
    /// 70-100 s (dev-swift 0e0f61a), so 90 s failed the first test of each web suite. A passing test returns as soon as
    /// its condition holds, so only a real failure waits the whole deadline.
    func until(_ condition: () -> Bool, timeout: Duration = .seconds(240)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while !condition() {
            if clock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    func until(async condition: () async -> Bool, timeout: Duration = .seconds(240)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while await !condition() {
            if clock.now > deadline { return false }
            try? await Task.sleep(for: .milliseconds(20))
        }
        return true
    }

    /// The document is loaded and every image has finished (loaded or failed): nothing more will be requested by itself.
    func settled(_ controller: ReaderWebController) async -> Bool {
        let script = "return document.readyState === 'complete' && Array.from(document.images).every((i) => i.complete);"
        return await until(async: { (try? await self.evaluate(script, in: controller) as? Bool) == true })
    }

    func evaluate(_ script: String, in controller: ReaderWebController) async throws -> Any? {
        try await controller.webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: ReaderWebController.world)
    }

    func imageTransport() -> MockTransport {
        MockTransport { request in
            HTTPResponse(statusCode: 200, headers: ["Content-Type": "image/png"], url: request.url, body: readerTestPixel)
        }
    }
}
