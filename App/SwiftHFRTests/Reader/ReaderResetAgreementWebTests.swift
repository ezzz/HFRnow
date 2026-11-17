import HFRModels
@testable import SwiftHFR
import Testing
import UIKit
import WebKit

/// #995: WebKit's reset of a new document reaches the scroll view and the page at different times, so a restore or a landing
/// sent once the scroll view was reset could be undone when the reset reached the page afterwards (`scrollY` 1000, then 0;
/// CI jobs 133772120017 and 133859276257). The page now waits until it shows what the scroll view showed when the app asked
/// (`from`). These tests deliver that late reset by hand, five frames after the request, in the real web view.
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

    @Test func aRestoreAskedBeforeTheResetReachedThePageSurvivesIt() async throws {
        let controller = try await pageAway()
        // The scroll view shows the top (`from` 0) while the page is still at 300; the reset reaches the page five frames
        // later. Without the wait the restore landed at frame 2 and the reset put the page back to 0.
        let script = Self.frames + """
            window.hfrReader.restoreScroll(1000, 0);
            await frames(5);
            window.scrollTo(0, 0);
            await frames(40);
            return window.scrollY;
            """
        let scrollY = (try await evaluate(script, in: controller) as? NSNumber)?.doubleValue ?? -1
        #expect(abs(scrollY - 1000) <= 1, "scrollY: \(scrollY)")
    }

    @Test func aLandingAskedBeforeTheResetReachedThePageSurvivesIt() async throws {
        let controller = try await pageAway()
        let script = Self.frames + """
            window.hfrReader.landOnPost(2, 0);
            await frames(5);
            window.scrollTo(0, 0);
            await frames(40);
            return Math.round(document.getElementById('t2').getBoundingClientRect().top);
            """
        let top = (try await evaluate(script, in: controller) as? NSNumber)?.intValue ?? -1
        #expect(top == 0, "message 2 at \(top), not at the top")
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
}
