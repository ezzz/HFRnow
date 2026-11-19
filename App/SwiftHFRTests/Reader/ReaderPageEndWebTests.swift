import HFRModels
@testable import SwiftHFR
import Testing
import UIKit
import WebKit

/// Issue #820 in the real web view: `reader.js` reports the page's end as legacy's `notifyScrollState` did (within 2 points of
/// the bottom, `MessagesView.swift:1013-1035` @ 87fe0d1c), with the page under the bars; each post's header has the legacy "+" (#594).
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
        let options = ReaderRenderOptions(showsMessageMenus: true)
        let html = TopicHTMLBuilder.document(for: page, token: token, options: options)
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
        // Ready comes from the page before the scroll view has the document (`showsDocument`): the end computed from the blank
        // page's size is the top, and the way back's target was then out of reach (#995).
        let scrollView = controller.webView.scrollView
        #expect(await showsDocument(controller), "the scroll view never took the document: \(scrollView.contentSize)")
        // The page scrolls itself: a native `setContentOffset` can be undone by a late layout (`ReaderInsetsWebTests.scrollPage`).
        // CI job 133090341114 showed the way back sent once and never applied (`window.scrollTo(0, 0)`, the scroll view stayed
        // at its end, offset 4356): the scroll is sent again until the scroll view is there, then the report is checked. A
        // failure of the first wait is a scroll that never happened; of the second, a report `reader.js` did not send.
        // The way back goes through `scrollPage(toScrollY:)`, which checks the page's side too (#934).
        let last = { scrollView.contentSize.height + bars.bottom - scrollView.bounds.height }
        let atEnd = await until(async: {
            _ = try? await evaluate("window.scrollTo(0, document.documentElement.scrollHeight); return true;", in: controller)
            return abs(scrollView.contentOffset.y - last()) <= 2
        }, timeout: .seconds(60))
        #expect(atEnd, "the page never reached its end: offset \(scrollView.contentOffset), last \(last())")
        #expect(await until { ends.reports.last == true }, "reports: \(ends.reports), offset \(scrollView.contentOffset)")
        // 20 points before the end is not the end: an end reported early (a viewport that counts the bars) fails here.
        let nearEnd = last() - 20
        // `scrollY` counts from the bars' edge (`ReaderInsetsWebTests`).
        let backed = await scrollPage(toScrollY: Double(nearEnd + bars.top), in: controller, tolerance: 2)
        #expect(backed, "the page never came back 20 points: offset \(scrollView.contentOffset), target \(nearEnd)")
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

    /// The page ends `FloatingSpacing.gap` above the bottom bar (operator, #820, 2026-11-16), not the old 2em, with no end-of-page
    /// hint in the flow (#1207).
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
