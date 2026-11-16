import HFRModels
@testable import SwiftHFR
import Testing
import UIKit
import WebKit

/// Issue #820 in the real web view: `reader.js` reports the page's end as legacy's `notifyScrollState` did (within 2 points of
/// the bottom, `MessagesView.swift:1013-1035` @ 87fe0d1c), with the page under the bars; the page ends with the pull hint and
/// each post's header with the legacy "+" (#594).
@MainActor
@Suite(.serialized)
struct ReaderPageEndWebTests: ReaderWebTesting {
    private let bars = UIEdgeInsets(top: 100, left: 0, bottom: 50, right: 0)

    private final class Ends {
        var reports: [Bool] = []
    }

    private func documentOf(height: Int, token: Int) -> ReaderDocument {
        let message = ReaderMessage(
            numreponse: 1, author: "auteur", isDeleted: false, isContinuation: false, avatarURL: nil, dateText: "",
            editNote: nil, quotedByCount: nil, content: MessageContent(html: "<div style=\"height:\(height)px\">m</div>")
        )
        let page = ReaderPage(topicID: readerTopic, title: "T", currentPage: 1, maxPage: 1, messages: [message])
        let html = TopicHTMLBuilder.document(for: page, token: token, options: ReaderRenderOptions(showsMessageMenus: true))
        return ReaderDocument(token: token, html: html, anchor: nil, keepsScrollPosition: false)
    }

    private func recording(_ controller: ReaderWebController) -> Ends {
        let ends = Ends()
        controller.events.pageEnd = { atEnd, _ in ends.reports.append(atEnd) }
        return ends
    }

    @Test func aTallPageReportsItsEndOnlyWhenItIsScrolledThere() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.obscuredInsets = bars
        let ends = recording(controller)
        controller.show(documentOf(height: 5000, token: 1))
        #expect(await until { recorder.ready == [1] && !ends.reports.isEmpty })
        #expect(ends.reports.last == false, "reports: \(ends.reports)")
        // The page scrolls itself: a native `setContentOffset` can be undone by a late layout (`ReaderInsetsWebTests.scrollPage`).
        // CI job 133090341114 showed the way back sent once and never applied (`window.scrollTo(0, 0)`, the scroll view stayed
        // at its end, offset 4356): the scroll is sent again until the scroll view is there, then the report is checked. A
        // failure of the first wait is a scroll that never happened; of the second, a report `reader.js` did not send.
        // The same lost-report symptom fails other reader web tests now and then, with WebContent trouble in the log (#934).
        let scrollView = controller.webView.scrollView
        let last = { scrollView.contentSize.height + bars.bottom - scrollView.bounds.height }
        let atEnd = await until(async: {
            _ = try? await evaluate("window.scrollTo(0, document.documentElement.scrollHeight); return true;", in: controller)
            return abs(scrollView.contentOffset.y - last()) <= 2
        }, timeout: .seconds(60))
        #expect(atEnd, "the page never reached its end: offset \(scrollView.contentOffset), last \(last())")
        #expect(await until { ends.reports.last == true }, "reports: \(ends.reports), offset \(scrollView.contentOffset)")
        let atTop = await until(async: {
            _ = try? await evaluate("window.scrollTo(0, 0); return true;", in: controller)
            return WebKitResetWatch.isAtTop(scrollView)
        }, timeout: .seconds(60))
        #expect(atTop, "the page never came back to its top: offset \(scrollView.contentOffset)")
        #expect(await until { ends.reports.last == false }, "reports: \(ends.reports), offset \(scrollView.contentOffset)")
    }

    /// A page shorter than the screen shows its end at once: the end-of-page bar is there without a scroll.
    @Test func aShortPageIsAtItsEndFromTheStart() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.obscuredInsets = bars
        let ends = recording(controller)
        controller.show(documentOf(height: 100, token: 1))
        #expect(await until { recorder.ready == [1] && ends.reports.last == true }, "reports: \(ends.reports)")
    }

    /// The page ends `FloatingSpacing.gap` above the bottom bar (operator, #820, 2026-11-16), not the old 2em, and the hint is not
    /// in the page: the app draws it under the page's end.
    @Test func thePageEndsTheSharedGapAboveTheBarWithNoHintInTheFlow() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.show(documentOf(height: 100, token: 1))
        #expect(await until { recorder.ready == [1] })
        let script = """
            return [getComputedStyle(document.body).paddingBottom, String(document.querySelectorAll(".pull-hint").length)];
            """
        let found = try #require(try await evaluate(script, in: controller) as? [String])
        #expect(found == ["\(Int(FloatingSpacing.gap))px", "0"])
    }
}
