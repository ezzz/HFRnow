import HFRModels
@testable import SwiftHFR
import Testing
import UIKit
import WebKit

/// LOT-186: the page runs under the bars. In the real web view: a message lands below the top bar, the message hidden under
/// it is not the reading position (LOT-111), and a refresh reopens at the same message when a banner came or went.
@MainActor
@Suite(.serialized)
struct ReaderInsetsWebTests: ReaderWebTesting {
    /// Navigation bar plus a banner over the page, and the bottom bar.
    private let bars = UIEdgeInsets(top: 100, left: 0, bottom: 50, right: 0)

    private func tallDocument(token: Int, anchor: Int? = nil, keepsScrollPosition: Bool = false) -> ReaderDocument {
        func message(_ number: Int) -> ReaderMessage {
            ReaderMessage(
                numreponse: number, author: "auteur", isDeleted: false, isContinuation: false, avatarURL: nil,
                dateText: "", editNote: nil, quotedByCount: nil,
                content: MessageContent(html: "<div style=\"height:1500px\">m\(number)</div>")
            )
        }
        let page = ReaderPage(
            topicID: readerTopic, title: "T", currentPage: 1, maxPage: 1, messages: [message(1), message(2), message(3)]
        )
        return ReaderDocument(
            token: token, html: TopicHTMLBuilder.document(for: page, token: token), anchor: anchor,
            keepsScrollPosition: keepsScrollPosition
        )
    }

    /// The top of message `post` in document coordinates (the scroll view's content coordinates at zoom 1).
    private func top(of post: Int, in controller: ReaderWebController) async throws -> CGFloat {
        let script = "const box = document.getElementById('t\(post)').getBoundingClientRect(); return box.top + window.scrollY;"
        return CGFloat((try await evaluate(script, in: controller) as? NSNumber)?.doubleValue ?? -1)
    }

    @Test func theInsetsReachWebKitAndTheScrollViewAndThePageStartsBelowTheBar() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.obscuredInsets = bars
        #expect(controller.webView.obscuredContentInsets == bars)
        #expect(controller.webView.scrollView.contentInset == bars)
        #expect(controller.webView.scrollView.contentInsetAdjustmentBehavior == .never)
        controller.show(tallDocument(token: 1))
        #expect(await until { recorder.ready == [1] })
        let scrollView = controller.webView.scrollView
        #expect(await until { abs(scrollView.contentOffset.y + bars.top) <= 1 }, "offset: \(scrollView.contentOffset)")
    }

    /// Issue #566: the screen goes away while a tall page is still loading, then comes back with the same document. The
    /// stopped load never reports ready: the controller must load the document again rather than skip it as already shown.
    @Test func aDocumentStoppedBeforeItWasReadyLoadsAgainWhenShownAgain() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.obscuredInsets = bars
        let document = tallDocument(token: 1)
        controller.show(document)
        controller.stopLoading()
        // The stop must really abort the navigation, or this test would pass without the fix too.
        #expect(await until({ !recorder.ready.isEmpty }, timeout: .seconds(2)) == false, "ready: \(recorder.ready)")
        // A hidden view's re-render shows nothing while stopped; the screen coming back does.
        controller.show(document)
        controller.resume()
        controller.show(document)
        #expect(await until({ recorder.ready == [1] }, timeout: .seconds(120)), "ready: \(recorder.ready)")
    }

    /// Fable finding 1: a page that kills the content process before it is ready is loaded once more, then reported.
    @Test func aDocumentWhoseContentProcessDiesTwiceBeforeReadyIsReported() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.show(tallDocument(token: 1))
        controller.webViewWebContentProcessDidTerminate(controller.webView)
        #expect(recorder.failed.isEmpty)
        controller.webViewWebContentProcessDidTerminate(controller.webView)
        #expect(recorder.failed == [1])
    }

    /// CodeRabbit: after a crash of a page already shown, the reload is a new load: its failures are reported too.
    @Test func theReloadOfAShownDocumentAfterACrashIsReportedWhenItFails() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.show(tallDocument(token: 1))
        #expect(await until { recorder.ready == [1] })
        controller.webViewWebContentProcessDidTerminate(controller.webView) // shown: reloaded
        controller.webViewWebContentProcessDidTerminate(controller.webView) // not ready again: reloaded once
        #expect(recorder.failed.isEmpty)
        controller.webViewWebContentProcessDidTerminate(controller.webView)
        #expect(recorder.failed == [1])
    }

    /// #1188: iOS killed the content process while the member read far below the flag message. The reload lands on the last
    /// message the page reported, not on the document's anchor.
    @Test func aReloadAfterProcessTerminationLandsOnTheLastReportedPost() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.obscuredInsets = bars
        let document = tallDocument(token: 1, anchor: 1)
        controller.show(document)
        #expect(await until { recorder.ready == [1] })
        let scrollView = controller.webView.scrollView
        // The landing on the anchor is done, so its own report is in before the member's.
        let anchorTop = try await top(of: 1, in: controller)
        #expect(await until { abs(scrollView.contentOffset.y + bars.top - anchorTop) <= 2 })
        _ = controller.handle(.position(post: 2), in: document)

        controller.webViewWebContentProcessDidTerminate(controller.webView)

        #expect(await until { recorder.ready == [1, 1] }, "ready: \(recorder.ready)")
        let messageTop = try await top(of: 2, in: controller)
        #expect(messageTop > 1000)
        #expect(
            await until { abs(scrollView.contentOffset.y + bars.top - messageTop) <= 2 },
            "offset \(scrollView.contentOffset.y), message at \(messageTop): the reload did not land on the last reported post"
        )
    }

    /// #1188: a third-party image the member tapped is still allowed when the page asks again after the reload.
    @Test func aTappedImageIsLoadedAgainAfterAContentProcessReload() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        let shown = tallDocument(token: 1)
        controller.show(shown)
        #expect(await until { recorder.ready == [1] })
        let photo = "https://i.imgur.com/photo.jpg"
        #expect(controller.decisions(for: [photo]) == [ImageDecision.tap.rawValue])
        #expect(controller.handle(.tap(url: photo), in: shown) as? Bool == true)

        controller.webViewWebContentProcessDidTerminate(controller.webView)

        #expect(controller.decisions(for: [photo]) == [ImageDecision.load.rawValue])
        // Another document starts without that consent.
        controller.show(tallDocument(token: 2))
        #expect(controller.decisions(for: [photo]) == [ImageDecision.tap.rawValue])
    }

    @Test func aMessageLandsBelowTheTopBar() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.obscuredInsets = bars
        controller.show(tallDocument(token: 1, anchor: 2))
        #expect(await until { recorder.ready == [1] })
        let messageTop = try await top(of: 2, in: controller)
        #expect(messageTop > 1000)
        let scrollView = controller.webView.scrollView
        #expect(
            await until { abs(scrollView.contentOffset.y + bars.top - messageTop) <= 2 },
            "offset \(scrollView.contentOffset.y), message at \(messageTop): the message is under the bar"
        )
    }

    /// Scrolls the page itself to `readingTop` (`scrollY`) until the scroll view shows it below the bar too: a native
    /// `setContentOffset` reaches the page's `scrollY` and scroll events asynchronously, and can be undone by a late layout;
    /// one `window.scrollTo` was not always applied (`scrollPage(toScrollY:)`, #934). The first scroll gets the page's own
    /// answer time; the wait for both sides then lasts `deadline`, so a CI log (durations, not messages) tells which step of a
    /// test failed.
    private func scrollPage(to readingTop: CGFloat, in controller: ReaderWebController, deadline: Duration) async throws -> Bool {
        _ = try await evaluate("window.scrollTo(0, \(Double(readingTop))); return true;", in: controller)
        return await scrollPage(toScrollY: Double(readingTop), in: controller, timeout: deadline)
    }

    /// The refresh of document `token` restored `readingTop` after WebKit's reset, on both sides (#995). Until that reset the
    /// scroll view still shows the previous document, at the same reading top: the page's `scrollY` alone can read it before
    /// the reset puts it back to 0, the likely cause of CI job 133772120017 (`scrollY` 1000, then 0 once loaded, while the
    /// offset checks after it passed within the same 1 s test; #995's Mac traces show the two sides of the reset apart) and of 133770412196
    /// (the pinch-zoomed refresh).
    /// The watch ends at the reset, when the restore is sent; the page and the scroll view agree once the scroll view has
    /// applied the page's scroll: a page sent back for a moment by an older offset of the scroll view (#958) is waited out
    /// here, and a restore that is lost for good still fails.
    private func restored(
        _ readingTop: CGFloat, token: Int, in controller: ReaderWebController, timeout: Duration
    ) async -> Bool {
        await until(async: {
            let watch = controller.resetWatch
            guard watch.committedToken == token, watch.token == nil else { return false }
            guard let page = (try? await self.evaluate("return window.scrollY;", in: controller)) as? NSNumber else { return false }
            return abs(page.doubleValue - readingTop) <= 1 && abs(controller.readingTop - readingTop) <= 1
        }, timeout: timeout)
    }

    @Test func theMessageHiddenUnderTheTopBarIsNotTheReadingPosition() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        let reports = PositionReports()
        controller.events.position = { post, _ in reports.posts.append(post) }
        controller.obscuredInsets = bars
        controller.show(tallDocument(token: 1))
        #expect(await until { recorder.ready == [1] })
        #expect(await settled(controller))
        // A scroll made before WebKit's reset of the new document would be undone by it (`showsDocument`, #995): same class
        // as the refresh below, no failure seen here yet.
        #expect(await showsDocument(controller), "contentSize: \(controller.webView.scrollView.contentSize)")
        // Message 2 starts 10 points above the bar's edge: message 1 ends under the 100-point bar, so message 2 is the first
        // one the reader sees. `scrollY` is the content at the bar's edge (checked on the scroll view).
        let second = try await top(of: 2, in: controller)
        let offset = controller.webView.scrollView.contentOffset.y
        #expect(try await scrollPage(to: second + 10, in: controller, deadline: .seconds(15)), "offset: \(offset)")
        // A report may already have come from the load (message 1, at the top): wait for the one after the scroll. The
        // message under the bar would be reported as 1 again, which the page does not repeat, so 2 never comes.
        #expect(await until({ reports.posts.last == 2 }, timeout: .seconds(20)), "reported: \(reports.posts)")
    }

    @Test func aRefreshReopensAtTheSameMessageWhenTheBarsChanged() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.obscuredInsets = bars
        controller.show(tallDocument(token: 1))
        #expect(await until { recorder.ready == [1] })
        #expect(await settled(controller))
        // A scroll made before WebKit's reset of the new document would be undone by it (`showsDocument`, #995): same class
        // as the refresh below, no failure seen here yet.
        #expect(await showsDocument(controller), "contentSize: \(controller.webView.scrollView.contentSize)")
        let scrollView = controller.webView.scrollView
        // Content 1000 at the bar's edge: offset 900 under the 100-point bar.
        #expect(try await scrollPage(to: 1000, in: controller, deadline: .seconds(15)), "offset: \(scrollView.contentOffset.y)")
        // A banner appears above the page: the content at the bars' edge stays.
        controller.obscuredInsets.top = 160
        #expect(
            await until({ abs(scrollView.contentOffset.y - 840) <= 1 }, timeout: .seconds(10)), "offset: \(scrollView.contentOffset.y)"
        )
        #expect(abs(controller.readingTop - 1000) <= 1)
        // The page counts from the new bars' edge too: what a refresh restores is where the reader is.
        let scrollY = { [self] in ((try? await evaluate("return window.scrollY;", in: controller)) as? NSNumber)?.doubleValue }
        #expect(await until(async: { abs((await scrollY() ?? -1) - 1000) <= 1 }, timeout: .seconds(25)), "scrollY")
        // Every offset from here on goes into the failure messages: the order of the reset and the restore (#995).
        let history = OffsetHistory(of: scrollView)
        defer { history.stop() }
        // The refresh starts with the banner, which goes away before the new document is ready.
        controller.show(tallDocument(token: 2, keepsScrollPosition: true))
        controller.obscuredInsets.top = 100
        #expect(await until({ recorder.ready == [1, 2] }, timeout: .seconds(90)), "ready: \(recorder.ready)")
        // Issue #642: the scroll view still shows the old document's offset, already 900 under the 100-point bar, when the
        // new one is ready; its reset to the top and the restore come after. The restore waits for that reset (#772): sent
        // before it, it was undone now and then on a loaded runner. The new page's `scrollY` alone does not tell that the
        // restore happened: before the reset it can be the old offset's (`restored`).
        let restore = await restored(1000, token: 2, in: controller, timeout: .seconds(30))
        let restoreState = await restore ? "" : scrollState(of: controller)
        #expect(restore, "restored: \(restoreState); offsets: \(history.description)")
        // Still there once the document has finished loading (a late layout must not undo the restore).
        #expect(await settled(controller))
        let loadedScrollY = await scrollY() ?? -1
        #expect(abs(loadedScrollY - 1000) <= 1, "scrollY after load: \(loadedScrollY); offsets: \(history.description)")
        // The scroll view follows the page's scroll asynchronously.
        #expect(
            await until({ abs(scrollView.contentOffset.y - 900) <= 1 }, timeout: .seconds(30)),
            "offset: \(scrollView.contentOffset.y); offsets: \(history.description)"
        )
        #expect(abs(controller.readingTop - 1000) <= 1)
    }

    /// Issue #587: the scroll view counts a pinch-zoomed page in points `zoomScale` times larger than `window.scrollTo`'s CSS
    /// pixels, while the bars' inset is not scaled; a refresh must still reopen at the content the reader was on.
    @Test func aRefreshAfterAPinchZoomReopensAtTheSameMessage() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.obscuredInsets = bars
        controller.show(tallDocument(token: 1))
        #expect(await until { recorder.ready == [1] })
        #expect(await settled(controller))
        // A scroll made before WebKit's reset of the new document would be undone by it (`showsDocument`, #995): same class
        // as the refresh below, no failure seen here yet.
        #expect(await showsDocument(controller), "contentSize: \(controller.webView.scrollView.contentSize)")
        let scrollView = controller.webView.scrollView
        #expect(try await scrollPage(to: 1000, in: controller, deadline: .seconds(15)), "offset: \(scrollView.contentOffset.y)")
        scrollView.setZoomScale(2, animated: false)
        #expect(abs(scrollView.zoomScale - 2) < 0.01, "zoomScale: \(scrollView.zoomScale)")
        // The CSS content at the bars' edge: the scroll view's points under the (unscaled) bar, divided by the zoom. The page's
        // own `visualViewport.pageTop` is not a usable reference: it does not follow a native `setZoomScale` (read 1000 here).
        let before = (scrollView.contentOffset.y + controller.obscuredInsets.top) / scrollView.zoomScale
        #expect(before > 0, "edge: \(before)")
        let history = OffsetHistory(of: scrollView)
        defer { history.stop() }
        controller.show(tallDocument(token: 2, keepsScrollPosition: true))
        #expect(await until({ recorder.ready == [1, 2] }, timeout: .seconds(90)), "ready: \(recorder.ready)")
        let scrollY = { [self] in ((try? await evaluate("return window.scrollY;", in: controller)) as? NSNumber)?.doubleValue }
        // After WebKit's reset, on both sides (`restored`, #995).
        let restore = await restored(before, token: 2, in: controller, timeout: .seconds(30))
        let restoreState = await restore ? "" : scrollState(of: controller)
        #expect(restore, "restored, before \(before): \(restoreState); offsets: \(history.description)")
        #expect(await settled(controller))
        let after = await scrollY() ?? -1
        #expect(abs(after - before) <= 1, "scrollY after load: \(after), before \(before); offsets: \(history.description)")
        #expect(abs(scrollView.zoomScale - 1) < 0.01, "zoomScale after reload: \(scrollView.zoomScale)")
    }

    /// Fable on #662: the restore waits for animation frames, which a hidden page does not draw. No native
    /// call may wait for them, or a reader refreshed while covered and then dropped would never be freed.
    ///
    /// The page leaves its window once ready, and the restore a refresh sends (`scroll(toReadingTop:)`, called by
    /// `documentIsReady`) goes out only once the page says it is hidden, with a probe that waits for two frames sent first. A
    /// load started while already hidden made the test depend on WebKit running a hidden page's load to the end, which a busy
    /// CI simulator did not always do (issue #801); hiding at `ready` raced WebKit's deferred visibility change (Fable on
    /// #841). Now the restore always reaches a page that draws no frames, and the probe answering would say otherwise. The
    /// controller's own calls into the page wait for no answer (#772): one pending on the hidden page held the controller.
    @Test func aRestoreWhileHiddenDoesNotKeepTheControllerAlive() async throws {
        weak var weakController: ReaderWebController?
        // Kept outside the controller's scope, so the probe's call stays pending while the controller is released.
        var hiddenWebView: WKWebView?
        let framesWhileHidden = TestEvent()
        let probe = "await new Promise((done) => requestAnimationFrame(() => requestAnimationFrame(done))); return true;"
        do {
            let (controller, recorder) = makeController(transport: imageTransport())
            weakController = controller
            hiddenWebView = controller.webView
            controller.obscuredInsets = bars
            controller.show(tallDocument(token: 1))
            #expect(await until { recorder.ready == [1] })
            controller.webView.removeFromSuperview()
            let visibility = "return document.visibilityState;"
            #expect(
                await until(async: { (try? await self.evaluate(visibility, in: controller) as? String) == "hidden" }),
                "the page out of its window never reported itself hidden"
            )
            controller.webView.callAsyncJavaScript(probe, arguments: [:], in: nil, in: ReaderWebController.world) { result in
                if case .success = result { framesWhileHidden.fire() }
            }
            controller.scroll(toReadingTop: 1000)
        }
        #expect(await until({ weakController == nil }, timeout: .seconds(30)))
        #expect(!framesWhileHidden.hasFired, "the hidden page drew frames: the restore was not shown to reach a hidden page")
        withExtendedLifetime(hiddenWebView) {}
    }
}
