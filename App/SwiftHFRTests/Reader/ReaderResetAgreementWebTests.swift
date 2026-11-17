import HFRModels
@testable import SwiftHFR
import Testing
import UIKit
import WebKit

/// #995: WebKit's reset of a new document reaches the scroll view and the page at different times, so a restore or a landing
/// sent once the scroll view was reset could be undone when the reset reached the page afterwards (`scrollY` 1000, then 0;
/// CI jobs 133772120017 and 133859276257). The page now waits until it shows what the scroll view showed when the app asked
/// (`from`), then scrolls at once. These tests deliver that late reset by hand, five frames after the request, in the real web
/// view, and check both halves: the page waited, and it scrolled as soon as it agreed, long before the 30-frame cap.
@MainActor
@Suite(.serialized)
struct ReaderResetAgreementWebTests: ReaderWebTesting {
    /// Waits `n` animation frames in the page.
    private static let frames = """
        const frames = (n) => new Promise((done) => {
          const step = () => { if (n <= 0) { done(); return; } n -= 1; requestAnimationFrame(step); };
          requestAnimationFrame(step);
        });
        """

    private func tallDocument() -> ReaderDocument {
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
        return ReaderDocument(token: 1, html: TopicHTMLBuilder.document(for: page, token: 1), anchor: nil, keepsScrollPosition: false)
    }

    /// A loaded page, its scroll view showing it, the page at `scrollY` 300: what the page still holds when the scroll view
    /// has already been reset to its top.
    private func pageAway(from top: Double = 300) async throws -> ReaderWebController {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.show(tallDocument())
        #expect(await until { recorder.ready == [1] })
        #expect(await settled(controller))
        #expect(await showsDocument(controller), "contentSize: \(controller.webView.scrollView.contentSize)")
        #expect(await scrollPage(toScrollY: top, in: controller, timeout: .seconds(30)), "the page never reached \(top)")
        return controller
    }

    /// Two numbers the page returns.
    private func pair(_ script: String, in controller: ReaderWebController) async throws -> (Double, Double) {
        let values = try await evaluate(script, in: controller) as? [NSNumber] ?? []
        return (values.first?.doubleValue ?? -1, values.dropFirst().first?.doubleValue ?? -1)
    }

    @Test func aRestoreWaitsForTheResetThenRunsAtOnce() async throws {
        let controller = try await pageAway()
        // The scroll view shows the top (`from` 0) while the page is still at 300; the reset reaches the page five frames
        // later. Without the wait the restore landed at frame 2 and the reset put the page back to 0; with a blind delay it
        // would come only at the cap.
        let script = Self.frames + """
            window.hfrReader.restoreScroll(1000, 0);
            await frames(5);
            const waited = window.scrollY;
            window.scrollTo(0, 0);
            await frames(3);
            return [waited, window.scrollY];
            """
        let (waited, fired) = try await pair(script, in: controller)
        #expect(abs(waited - 300) <= 1, "the restore did not wait for the reset: scrollY \(waited) at frame 5")
        #expect(abs(fired - 1000) <= 1, "the restore did not run once the page agreed: scrollY \(fired) 3 frames later")
    }

    @Test func aLandingWaitsForTheResetThenRunsAtOnce() async throws {
        let controller = try await pageAway()
        let script = Self.frames + """
            const top = () => Math.round(document.getElementById('t2').getBoundingClientRect().top);
            window.hfrReader.landOnPost(2, 0);
            await frames(5);
            const waited = top();
            window.scrollTo(0, 0);
            await frames(3);
            return [waited, top()];
            """
        let (waited, fired) = try await pair(script, in: controller)
        #expect(waited > 1000, "the landing did not wait for the reset: message 2 at \(waited) at frame 5")
        #expect(fired == 0, "the landing did not run once the page agreed: message 2 at \(fired) 3 frames later")
    }

    /// A page that never shows what the scroll view showed (no reset comes) is still scrolled, after the frame cap: the wait
    /// can delay a restore, never drop it.
    @Test func aRestoreWhoseResetNeverReachesThePageStillScrolls() async throws {
        let controller = try await pageAway()
        let script = Self.frames + """
            window.hfrReader.restoreScroll(1000, 0);
            await frames(45);
            return window.scrollY;
            """
        let scrollY = (try await evaluate(script, in: controller) as? NSNumber)?.doubleValue ?? -1
        #expect(abs(scrollY - 1000) <= 1, "scrollY: \(scrollY)")
    }

    /// Fable on #1044: the member touching the page during the wait takes it over; the restore must not yank them back.
    @Test func theMemberTouchingThePageDuringTheWaitCancelsTheRestore() async throws {
        let controller = try await pageAway()
        let script = Self.frames + """
            window.hfrReader.restoreScroll(1000, 0);
            await frames(3);
            window.dispatchEvent(new Event('wheel'));
            window.scrollTo(0, 0);
            await frames(40);
            return window.scrollY;
            """
        let scrollY = (try await evaluate(script, in: controller) as? NSNumber)?.doubleValue ?? -1
        #expect(scrollY <= 1, "the restore ran after the member took the page: scrollY \(scrollY)")
    }

    /// The native side hands the page the scroll view's reading top in CSS pixels, plain and pinch-zoomed (#587).
    @Test(arguments: [1.0, 2.0])
    func theRestoreAndTheLandingGetTheScrollViewsReadingTop(zoom: Double) async throws {
        let controller = try await pageAway()
        let scrollView = controller.webView.scrollView
        let recorder = """
            window.hfrReader.restoreScroll = (y, from) => { window.recordedRestore = [y, from]; return true; };
            window.hfrReader.landOnPost = (n, from) => { window.recordedLanding = [n, from]; return true; };
            return true;
            """
        _ = try await evaluate(recorder, in: controller)
        // Zoom, expectation and calls in one main-actor turn: WebKit may set the zoom back while the test awaits.
        if zoom != 1 { scrollView.setZoomScale(zoom, animated: false) }
        let expected = Double((scrollView.contentOffset.y + controller.obscuredInsets.top) / scrollView.zoomScale)
        let zoomAtCall = scrollView.zoomScale
        controller.scroll(toReadingTop: 1000)
        controller.scroll(to: 2, landing: true)
        let read = """
            return [window.recordedRestore ? window.recordedRestore[1] : -1, window.recordedLanding ? window.recordedLanding[1] : -1];
            """
        let both = await until(async: {
            guard let (restore, landing) = try? await self.pair(read, in: controller) else { return false }
            return abs(restore - expected) <= 1 && abs(landing - expected) <= 1
        }, timeout: .seconds(30))
        let seen = (try? await pair(read, in: controller)).map { "\($0)" } ?? "none"
        #expect(both, "from: \(seen), expected \(expected) at zoom \(zoomAtCall)")
    }
}
