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
    var failed: [Int] = []
    var links: [URL] = []
    /// Video taps as (post, index, token).
    var videos: [[Int]] = []
    /// Image viewer openings as (images, selected index).
    var viewers: [(images: [GalleryImage], index: Int)] = []
    /// The feedback sentences the controller sent.
    var notices: [String] = []
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
            ready: { recorder.ready.append($0) }, failed: { recorder.failed.append($0) }, link: { recorder.links.append($0) },
            video: { recorder.videos.append([$0, $1, $2]) },
            image: { images, index, _ in recorder.viewers.append((images, index)) },
            notice: { recorder.notices.append($0) }
        )
        recorder.window = hostInWindow(controller.webView)
        return (controller, recorder)
    }

    func document(
        token: Int, content: String = readerHostileContent, embeds: [MessageEmbed] = []
    ) -> ReaderDocument {
        let message = ReaderMessage(
            numreponse: 7, author: "auteur", isDeleted: false, isContinuation: false,
            avatarURL: URL(string: "https://forum-images.hardware.fr/avatars/a.png"), dateText: "27-10-2026 10:00:00",
            editNote: nil, quotedByCount: nil, content: MessageContent(html: content, embeds: embeds)
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

    /// A WebKit call of `condition` gets only what is left of `timeout` (`WaitBudget`).
    func until(async condition: () async -> Bool, timeout: Duration = .seconds(240)) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        return await WaitBudget.$deadline.withValue(deadline) {
            while await !condition() {
                if clock.now > deadline { return false }
                try? await Task.sleep(for: .milliseconds(20))
            }
            return true
        }
    }

    /// Scrolls the page itself to `scrollY` (CSS pixels from the bars' edge, the reading top) and returns true once the page
    /// and the scroll view are both there. One `window.scrollTo` was not always enough on a loaded simulator: CI job
    /// 133090341114 saw the way back to the top sent once and never applied (the scroll view stayed at the page's end), so the
    /// scroll is sent again until both sides agree, and a test checks what the page reported, not whether one request went
    /// through. Why that scroll was lost is not established (#934). `scrollY` must be reachable (not past the page's end); both
    /// sides must be within `tolerance` of it.
    func scrollPage(
        toScrollY scrollY: Double, in controller: ReaderWebController, tolerance: Double = 1, timeout: Duration = .seconds(60)
    ) async -> Bool {
        await until(async: {
            let script = "window.scrollTo(0, \(scrollY)); return window.scrollY;"
            guard let page = (try? await self.evaluate(script, in: controller)) as? NSNumber else { return false }
            return abs(page.doubleValue - scrollY) <= tolerance && abs(Double(controller.readingTop) - scrollY) <= tolerance
        }, timeout: timeout)
    }

    /// The scroll view shows the shown document (#995): its content height is the page's own `scrollHeight`. The page reports
    /// ready from its own process, before the UI process applies the document's first layer-tree commit, which sets the scroll
    /// view's content size and resets it to the document's top (`WebKitResetWatch`). Until then the scroll view keeps the blank
    /// page's size, the viewport under the bars (650 points in a test window of 800 under bars of 100 and 50): an end computed
    /// from it is the top, which the scroll view is already at (CI jobs 133712438518, 133717388761: target -120, band 0...650),
    /// and a scroll the page makes before that commit is undone by the reset. Only for a page taller than the viewport, whose
    /// `scrollHeight` cannot be the blank page's.
    func showsDocument(_ controller: ReaderWebController) async -> Bool {
        let scrollView = controller.webView.scrollView
        return await until(async: {
            let script = "return document.documentElement.scrollHeight;"
            guard let height = (try? await self.evaluate(script, in: controller)) as? NSNumber else { return false }
            return abs(scrollView.contentSize.height / scrollView.zoomScale - height.doubleValue) <= 1
        })
    }

    /// Where the page and its scroll view are, and whether a landing's reset is still watched, for a failure message.
    func scrollState(of controller: ReaderWebController) async -> String {
        let page = (try? await evaluate("return window.scrollY;", in: controller, timeout: .seconds(10))) as? NSNumber
        let watched = controller.resetWatch.token.map { "\($0)" } ?? "none"
        return "page scrollY \(page.map { "\($0.doubleValue)" } ?? "no answer"), scroll view reading top \(controller.readingTop), "
            + "reset watched for \(watched)"
    }

    /// The document is loaded and every image has finished (loaded or failed): nothing more will be requested by itself.
    func settled(_ controller: ReaderWebController) async -> Bool {
        let script = "return document.readyState === 'complete' && Array.from(document.images).every((i) => i.complete);"
        return await until(async: { (try? await self.evaluate(script, in: controller) as? Bool) == true })
    }

    /// Runs `script` in the reader's world. Throws `WaitTimeout` when no answer comes (a dead or suspended content process),
    /// so `until(async:)` and the tests fail at their deadline instead of hanging the CI job (issue #801).
    func evaluate(_ script: String, in controller: ReaderWebController, timeout: Duration = .seconds(120)) async throws -> Any? {
        let webView = controller.webView
        return try await answer(of: "the reader page", within: WaitBudget.cap(timeout)) {
            try await webView.callAsyncJavaScript(script, arguments: [:], in: nil, contentWorld: ReaderWebController.world)
        }
    }

    func imageTransport() -> MockTransport {
        MockTransport { request in
            HTTPResponse(statusCode: 200, headers: ["Content-Type": "image/png"], url: request.url, body: readerTestPixel)
        }
    }
}
