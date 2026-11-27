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

    /// What the page saw, counted in its own frames: the frame at which the test first delivered the reset by hand (-1: never;
    /// the page agrees only if the code under test waits for it), the frame at which the app's scroll ran (-1: not within the
    /// frames watched), and the page's `scrollY` at each frame for a failure message.
    private struct Agreement {
        let resetDeliveredAt: Int
        let ranAt: Int
        let trace: String
    }

    /// Asks `ask` (a restore or a landing whose `from` is 600) while the page is at 300, then, from frame `resetFrom` (nil:
    /// never), delivers the late reset by hand (the page moves to 600), and watches up to `frames` frames for `ran`.
    /// #1324: every ask of this suite that the page must not agree with by itself uses `from` 600, not 0, where WebKit's own
    /// reset puts a page: a late reset of the page's new document (#995) reaching it during a test (CI job 138855383148, the
    /// landing ran by frame 5 with the page at the top) neither agrees early for the test nor hides a scroll that ran. Frames
    /// are counted in the page, never timed. The reset is delivered again each frame until the scroll runs: a WebKit reset to
    /// 0 between two frames cannot undo the test's own one. The page calls its own frame callbacks first (registered first),
    /// so `ran` sees the scroll of the same frame.
    private func agreement(
        asking ask: String, ran: String, resetFrom: Int? = 5, frames: Int = 15, in controller: ReaderWebController
    ) async throws -> Agreement {
        let script = """
            const oneFrame = () => new Promise((done) => requestAnimationFrame(done));
            const ran = () => \(ran);
            const resetFrom = \(resetFrom ?? -1);
            \(ask);
            const trace = [];
            let resetDeliveredAt = -1;
            for (let frame = 1; frame <= \(frames); frame += 1) {
              await oneFrame();
              trace.push(frame + ':' + Math.round(window.scrollY));
              if (ran()) { return [resetDeliveredAt, frame, trace.join(' ')]; }
              if (resetFrom > 0 && frame >= resetFrom) {
                if (resetDeliveredAt < 0) { resetDeliveredAt = frame; }
                window.scrollTo(0, 600);
              }
            }
            return [resetDeliveredAt, -1, trace.join(' ')];
            """
        let values = try await evaluate(script, in: controller) as? [Any] ?? []
        return Agreement(
            resetDeliveredAt: (values.first as? NSNumber)?.intValue ?? -1,
            ranAt: (values.dropFirst().first as? NSNumber)?.intValue ?? -1,
            trace: values.dropFirst(2).first as? String ?? "no answer"
        )
    }

    /// Whether the page is at the restore's 1000.
    private static let restored = "Math.abs(window.scrollY - 1000) <= 1"

    @Test func aRestoreWaitsForTheResetThenRunsAtOnce() async throws {
        let controller = try await pageAway()
        // The scroll view shows 600 (`from`) while the page is still at 300; the reset reaches the page at frame 5. Without
        // the wait the restore ran at frame 2 and the reset undid it; with a blind delay it would come only at the cap (30).
        let result = try await agreement(
            asking: "window.hfrReader.restoreScroll(1000, 600)", ran: Self.restored, in: controller
        )
        #expect(result.resetDeliveredAt == 5, "the restore did not wait for the reset (scrollY by frame): \(result.trace)")
        #expect(
            result.ranAt > result.resetDeliveredAt && result.ranAt <= result.resetDeliveredAt + 3,
            "the restore did not run once the reset came at frame \(result.resetDeliveredAt) (scrollY by frame): \(result.trace)"
        )
    }

    @Test func aLandingWaitsForTheResetThenRunsAtOnce() async throws {
        let controller = try await pageAway()
        let result = try await agreement(
            asking: "window.hfrReader.landOnPost(2, 600)",
            ran: "Math.abs(document.getElementById('t2').getBoundingClientRect().top) <= 1", in: controller
        )
        #expect(result.resetDeliveredAt == 5, "the landing did not wait for the reset (scrollY by frame): \(result.trace)")
        #expect(
            result.ranAt > result.resetDeliveredAt && result.ranAt <= result.resetDeliveredAt + 3,
            "the landing did not run once the reset came at frame \(result.resetDeliveredAt) (scrollY by frame): \(result.trace)"
        )
    }

    /// A page that never shows what the scroll view showed (no reset comes) is still scrolled, at the frame cap (30, after the
    /// two first frames): the wait can delay a restore, never drop it. `from` 600: a WebKit reset to 0 during the wait does
    /// not let the restore run early and pass without reaching the cap (#1324).
    @Test func aRestoreWhoseResetNeverReachesThePageStillScrolls() async throws {
        let controller = try await pageAway()
        let result = try await agreement(
            asking: "window.hfrReader.restoreScroll(1000, 600)", ran: Self.restored, resetFrom: nil, frames: 45, in: controller
        )
        // -1: never ran within the 45 frames; under 30: ran before the cap with no reset delivered.
        #expect((30...40).contains(result.ranAt), "the restore did not run at the cap (scrollY by frame): \(result.trace)")
    }

    /// Fable on #1044: the member touching the page during the wait takes it over; the restore must not yank them back. The
    /// wheel comes at frame 3, the reset at frame 5: a restore not cancelled would run at once, or at the cap if a WebKit reset
    /// moved the page away again, both within the 45 frames watched; one that ran is seen, not hidden by a later scroll (#1324).
    @Test func theMemberTouchingThePageDuringTheWaitCancelsTheRestore() async throws {
        let controller = try await pageAway()
        let wheel = "requestAnimationFrame(() => requestAnimationFrame(() => requestAnimationFrame(() => "
            + "window.dispatchEvent(new Event('wheel')))))"
        let result = try await agreement(
            asking: "window.hfrReader.restoreScroll(1000, 600); \(wheel)", ran: Self.restored, frames: 45, in: controller
        )
        #expect(
            result.resetDeliveredAt == 5 && result.ranAt == -1,
            "the restore ran after the member took the page (scrollY by frame): \(result.trace)"
        )
    }

    /// Fable on #1044, round 2: a touch in the same millisecond as the ask still cancels it (counted, not timed).
    @Test func aTouchInTheSameTurnAsTheAskCancelsTheRestore() async throws {
        let controller = try await pageAway()
        let result = try await agreement(
            asking: "window.hfrReader.restoreScroll(1000, 600); window.dispatchEvent(new Event('touchstart'))",
            ran: Self.restored, frames: 45, in: controller
        )
        #expect(
            result.resetDeliveredAt == 5 && result.ranAt == -1,
            "the restore ran after a touch in the same turn (scrollY by frame): \(result.trace)"
        )
    }

    /// While the member moves the scroll view (`WebKitResetWatch.userScrolls`), the page gets no `from`: their reading top
    /// is a moving value it would never match, so it scrolls after its two frames, as before #995.
    @Test func noAgreementIsAskedWhileTheMemberScrolls() async throws {
        let controller = try await pageAway()
        controller.resetWatch.userScrolls = { _ in true }
        let recorder = """
            window.hfrReader.restoreScroll = (y, from) => { window.recordedFrom = from; return true; };
            return true;
            """
        _ = try await evaluate(recorder, in: controller)
        controller.scroll(toReadingTop: 1000)
        let read = """
            return window.recordedFrom === undefined ? 'none' : (window.recordedFrom === null ? 'null' : String(window.recordedFrom));
            """
        let seen = await until(async: { ((try? await self.evaluate(read, in: controller)) as? String) != "none" }, timeout: .seconds(30))
        let from = (try? await evaluate(read, in: controller)) as? String
        #expect(seen && from == "null", "from: \(from ?? "no answer")")
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
