import Foundation
import HFRModels
import HFRNetwork
@testable import SwiftHFR
import Testing
import WebKit

/// The reader's security envelope on a real web view (Fable's review of #257): consent, CSP, throttling, redirects.
@MainActor
@Suite(.serialized)
struct ReaderWebSecurityTests: ReaderWebTesting {
    /// Fable's probe: markup that names the app's scheme with `tap=1`, as an image (reached by WebKit's preload scanner
    /// before `reader.js` runs) and as a CSS background, must not reach a third party: consent lives in the app.
    @Test func markupCannotForgeATap() async throws {
        let transport = imageTransport()
        let (controller, recorder) = makeController(transport: transport)
        let probe = """
            <p><img src="hfrreader://image/?u=https%3A%2F%2Ftracker.example%2Fpixel.png&amp;tap=1" alt=""></p>
            <p style="background:url(hfrreader://image/?u=https%3A%2F%2Ftracker.example%2Fbg.png&amp;tap=1)">fond</p>
            """
        controller.show(document(token: 1, content: probe))
        #expect(await until { recorder.ready == [1] }, "ready: \(recorder.ready)")
        #expect(await settled(controller))
        #expect(await until { controller.imageRequests.contains { $0.requested.lastPathComponent == "bg.png" } })
        #expect(!controller.imageRequests.contains { $0.requested.host() == "tracker.example" && $0.allowed })
        #expect(await transport.requests.allSatisfy { $0.url.host() != "tracker.example" })
    }

    /// A tap consents to that URL only, in that document only.
    @Test func aTapConsentsToOneURLInOneDocument() async throws {
        let transport = imageTransport()
        let (controller, recorder) = makeController(transport: transport)
        let content = """
            <p><img class="hfrplusimg" src="https://i.imgur.com/a.jpg" alt=""></p>
            <p><img class="hfrplusimg" src="https://i.imgur.com/b.jpg" alt=""></p>
            """
        controller.show(document(token: 1, content: content))
        #expect(await until { recorder.ready == [1] }, "ready: \(recorder.ready)")
        _ = try await evaluate("document.querySelector('button.image-tap').click(); return true;", in: controller)
        #expect(await until { controller.imageRequests.contains { $0.requested.lastPathComponent == "a.jpg" && $0.allowed } })
        #expect(await settled(controller))
        #expect(await transport.requests.map(\.url.lastPathComponent).filter { $0.hasSuffix(".jpg") } == ["a.jpg"])
        controller.show(document(token: 2, content: content))
        #expect(await until { recorder.ready == [1, 2] })
        #expect(await settled(controller))
        let placeholders = try await evaluate("return document.querySelectorAll('button.image-tap').length;", in: controller)
        #expect((placeholders as? NSNumber)?.intValue == 2)
    }

    /// With third parties allowed by the setting, a forum image that redirects to a third party is followed.
    @Test(arguments: [false, true])
    func aForumRedirectToAThirdPartyFollowsTheSetting(autoLoad: Bool) async throws {
        let transport = MockTransport { request in
            if request.url.host() == "forum-images.hardware.fr" {
                return HTTPResponse(statusCode: 302, headers: ["Location": "https://cdn.example/s.png"], url: request.url)
            }
            return HTTPResponse(statusCode: 200, headers: ["Content-Type": "image/png"], url: request.url, body: readerTestPixel)
        }
        let (controller, recorder) = makeController(transport: transport, autoLoad: autoLoad)
        controller.show(document(token: 1, content: "<p><img src=\"https://forum-images.hardware.fr/icones/s.gif\" alt=\"\"></p>"))
        #expect(await until { recorder.ready == [1] })
        #expect(await settled(controller))
        let reached = await transport.requests.contains { $0.url.host() == "cdn.example" }
        #expect(reached == autoLoad)
    }

    /// At most `maximumConcurrentImages` downloads run at once; the others wait and still complete.
    @Test func imageDownloadsAreThrottled() async throws {
        let counter = InFlightCounter()
        let transport = MockTransport { request in
            counter.enter()
            try? await Task.sleep(for: .milliseconds(100))
            counter.leave()
            return HTTPResponse(statusCode: 200, headers: ["Content-Type": "image/png"], url: request.url, body: readerTestPixel)
        }
        let (controller, recorder) = makeController(transport: transport, autoLoad: true)
        let images = (1...20).map { "<img class=\"hfrplusimg\" src=\"https://img.example/\($0).png\" alt=\"\">" }.joined()
        controller.show(document(token: 1, content: "<p>\(images)</p>"))
        #expect(await until { recorder.ready == [1] })
        #expect(await settled(controller))
        #expect(await transport.requests.filter { $0.url.host() == "img.example" }.count == 20)
        #expect(counter.peak <= ReaderWebController.maximumConcurrentImages, "peak \(counter.peak)")
        #expect(counter.peak > 1)
    }

    /// `<style>` elements are refused by the CSP; the sanitized `color:` attributes of the content still apply.
    @Test func styleElementsAreRefusedAndColourAttributesKept() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        let content = """
            <style>p.probe { color: rgb(1, 2, 3); }</style><p class="probe">x</p><p><span style="color:#ff0000">rouge</span></p>
            """
        controller.show(document(token: 1, content: content))
        #expect(await until { recorder.ready == [1] })
        let probe = try await evaluate("return getComputedStyle(document.querySelector('p.probe')).color;", in: controller) as? String
        #expect(probe != "rgb(1, 2, 3)")
        let red = try await evaluate("return getComputedStyle(document.querySelector('.content span')).color;", in: controller) as? String
        #expect(red == "rgb(255, 0, 0)")
    }

    /// The CSP header stops a remote `src` before any request, preload scanner included: a local server sees nothing.
    @Test func noRemoteRequestLeavesThePage() async throws {
        let server = try ConnectionCounter()
        defer { server.stop() }
        try await server.ready()
        let (controller, recorder) = makeController(transport: imageTransport())
        let remote = "http://127.0.0.1:\(server.port)"
        let content = """
            <p><img src="\(remote)/img.png" alt=""></p><p style="background:url(\(remote)/bg.png)">x</p>
            <link rel="stylesheet" href="\(remote)/s.css"><iframe src="\(remote)/frame"></iframe>
            """
        controller.show(document(token: 1, content: content))
        #expect(await until { recorder.ready == [1] })
        #expect(await settled(controller))
        try await Task.sleep(for: .seconds(1)) // absence cannot be polled: give a late request time to arrive
        #expect(server.connections == 0)
    }
}

/// Counts concurrent calls and keeps the peak.
private final class InFlightCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var current = 0
    private var maximum = 0

    var peak: Int { lock.withLock { maximum } }

    func enter() { lock.withLock { current += 1; maximum = max(maximum, current) } }

    func leave() { lock.withLock { current -= 1 } }
}
