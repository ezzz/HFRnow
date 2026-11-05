import Foundation
import HFRModels
import HFRNetwork
@testable import SwiftHFR
import Testing
import UIKit
import WebKit

/// The real web view, driven end to end: what the page may run, request and navigate to.
///
/// Serialized, with long deadlines: a cold CI simulator starts WebKit's processes slowly, and parallel web views compete.
@MainActor
@Suite(.serialized)
struct ReaderWebControllerTests: ReaderWebTesting {
    @Test func thePageRunsNoScriptAndRoutesEveryImageThroughThePolicy() async throws {
        let transport = imageTransport()
        let (controller, recorder) = makeController(transport: transport)
        controller.show(document(token: 1))
        #expect(await until { recorder.ready == [1] }, "ready: \(recorder.ready), images: \(controller.imageRequests.count)")
        // Images settle after DOMContentLoaded.
        #expect(await until { controller.imageRequests.count >= 3 }, "image requests: \(controller.imageRequests)")
        #expect(await settled(controller))

        let title = try await evaluate("return document.title;", in: controller) as? String
        #expect(title == "Titre")
        let requested = Set(await transport.requests.map(\.url.absoluteString))
        #expect(requested == [
            "https://forum-images.hardware.fr/icones/smile.gif", "https://forum-images.hardware.fr/icones/none.gif",
            "https://forum-images.hardware.fr/avatars/a.png"
        ])
        #expect(controller.imageRequests.allSatisfy { $0.allowed }, "image requests: \(controller.imageRequests)")
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
        #expect(await until { recorder.ready == [1] }, "ready: \(recorder.ready), images: \(controller.imageRequests.count)")
        let visibility = "return getComputedStyle(document.querySelector('div.masque')).visibility;"
        #expect(await until(async: { (try? await self.evaluate(visibility, in: controller) as? String) == "hidden" }))
        _ = try await evaluate("document.querySelector('table.spoiler td').click(); return true;", in: controller)
        #expect(try await evaluate(visibility, in: controller) as? String == "visible")
    }

    @Test func aTapLoadsAThirdPartyImageThroughTheCookielessClient() async throws {
        let transport = imageTransport()
        let (controller, recorder) = makeController(transport: transport)
        controller.show(document(token: 1))
        #expect(await until { recorder.ready == [1] }, "ready: \(recorder.ready), images: \(controller.imageRequests.count)")
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
        #expect(await until { recorder.ready == [1] }, "ready: \(recorder.ready), images: \(controller.imageRequests.count)")
        #expect(await until { controller.imageRequests.contains { $0.requested.host() == "i.imgur.com" } })
        #expect(!controller.imageRequests.contains { $0.requested.host() == "192.168.1.1" })
    }

    @Test func aTappedLinkLeavesTheReaderToTheApp() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.show(document(token: 1))
        #expect(await until { recorder.ready == [1] }, "ready: \(recorder.ready), images: \(controller.imageRequests.count)")
        _ = try await evaluate("document.querySelector('a[href=\"https://example.com/page\"]').click(); return true;", in: controller)
        #expect(await until { recorder.links == [URL(string: "https://example.com/page")] })
        #expect(controller.webView.url == ReaderWebController.pageURL(token: 1))
    }

    @Test func onlyTheLatestDocumentReportsReady() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.show(document(token: 1))
        controller.show(document(token: 2, content: "<p>deux</p>"))
        #expect(await until { recorder.ready.contains(2) })
        #expect(await settled(controller))
        #expect(recorder.ready == [2])
        let text = try await evaluate("return document.querySelector('.content').textContent;", in: controller) as? String
        #expect(text == "deux")
    }

    /// A real page (`R28`: 42 posted images, spoiler, smileys) in tap mode: only forum images reach the client.
    @Test func aRealPageRequestsOnlyForumImagesBeforeATap() async throws {
        let page = try LiveTopicPageSourceTests.readerPage(of: "R28-topic-images-videos-anon.html")
        let posted = page.messages.flatMap(\.content.images)
        #expect(!posted.isEmpty)
        let transport = imageTransport()
        let (controller, recorder) = makeController(transport: transport)
        controller.show(ReaderDocument(
            token: 1, html: TopicHTMLBuilder.document(for: page, token: 1), anchor: nil, keepsScrollPosition: false
        ))
        #expect(await until { recorder.ready == [1] }, "ready: \(recorder.ready)")
        #expect(await settled(controller))
        let hosts = Set(await transport.requests.compactMap { $0.url.host() })
        #expect(hosts.isSubset(of: ["forum-images.hardware.fr"]), "requested: \(hosts)")
        let placeholders = try await evaluate("return document.querySelectorAll('button.image-tap').length;", in: controller)
        #expect(((placeholders as? NSNumber)?.intValue ?? 0) > 0)
        let title = try await evaluate("return document.title;", in: controller) as? String
        #expect(title == page.title)
    }
}

/// LOT-111: landing on a message and reporting the topmost one, in the real web view.
@MainActor
@Suite(.serialized)
struct ReaderLandingWebTests: ReaderWebTesting {
    private func landingDocument(anchor: Int) -> ReaderDocument {
        func message(_ number: Int, height: Int) -> ReaderMessage {
            ReaderMessage(
                numreponse: number, author: "auteur", isDeleted: false, isContinuation: false, avatarURL: nil,
                dateText: "", editNote: nil, quotedByCount: nil,
                content: MessageContent(html: "<div style=\"height:\(height)px\">m\(number)</div>")
            )
        }
        let page = ReaderPage(
            topicID: readerTopic, title: "T", currentPage: 1, maxPage: 1, messages: [message(1, height: 3000), message(2, height: 3000)]
        )
        return ReaderDocument(
            token: 1, html: TopicHTMLBuilder.document(for: page, token: 1), anchor: anchor, keepsScrollPosition: false
        )
    }

    @Test func aDocumentLandsOnItsAnchorAndReportsTheTopmostMessageOnceScrollingStops() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        let reports = PositionReports()
        controller.events.position = { post, _ in reports.posts.append(post) }
        controller.show(landingDocument(anchor: 2))
        #expect(await until { recorder.ready == [1] })
        let top = "return Math.round(document.getElementById('t2').getBoundingClientRect().top);"
        #expect(await until(async: { (try? await self.evaluate(top, in: controller) as? Int) == 0 }))
        _ = try await evaluate("window.scrollTo(0, 0); return true;", in: controller)
        #expect(await until { reports.posts.contains(1) }, "reported: \(reports.posts)")
    }
}

/// The messages the web view reported as topmost.
@MainActor
final class PositionReports {
    var posts: [Int] = []
}
