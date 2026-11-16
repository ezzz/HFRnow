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

    private func documentOf(height: Int, token: Int, pullHint: Bool = true) -> ReaderDocument {
        let message = ReaderMessage(
            numreponse: 1, author: "auteur", isDeleted: false, isContinuation: false, avatarURL: nil, dateText: "",
            editNote: nil, quotedByCount: nil, content: MessageContent(html: "<div style=\"height:\(height)px\">m</div>")
        )
        let page = ReaderPage(topicID: readerTopic, title: "T", currentPage: 1, maxPage: 1, messages: [message])
        let options = ReaderRenderOptions(showsMessageMenus: true, offersPullToRefresh: pullHint)
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
        // 20 points before the end is not the end: an end reported early (a viewport that counts the bars) fails here.
        let nearEnd = last() - 20
        let backed = await until(async: {
            let scrollY = Double(nearEnd + bars.top) // `scrollY` counts from the bars' edge (`ReaderInsetsWebTests`)
            _ = try? await evaluate("window.scrollTo(0, \(scrollY)); return true;", in: controller)
            return abs(scrollView.contentOffset.y - nearEnd) <= 2
        }, timeout: .seconds(60))
        #expect(backed, "the page never came back 20 points: offset \(scrollView.contentOffset), target \(nearEnd)")
        #expect(await until { ends.reports.last == false }, "reports: \(ends.reports), offset \(scrollView.contentOffset)")
    }

    /// Operator decision of 2026-11-16 on #932: at rest at the page's end, the hint shows `FloatingSpacing.gap` under the last
    /// message, inside what the bars leave visible: above the floating bottom bar, never under it.
    @Test func atRestTheHintSitsTheSharedGapUnderTheLastMessageAboveTheBar() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.obscuredInsets = bars
        controller.show(documentOf(height: 3000, token: 1))
        #expect(await until { recorder.ready == [1] })
        let scrollView = controller.webView.scrollView
        let last = { scrollView.contentSize.height + bars.bottom - scrollView.bounds.height }
        let atEnd = await until(async: {
            _ = try? await evaluate("window.scrollTo(0, document.documentElement.scrollHeight); return true;", in: controller)
            return abs(scrollView.contentOffset.y - last()) <= 2
        }, timeout: .seconds(60))
        #expect(atEnd, "the page never reached its end: offset \(scrollView.contentOffset), last \(last())")
        // Document coordinates are the scroll view's content coordinates at zoom 1 (`ReaderInsetsWebTests`).
        let script = """
            const hint = document.querySelector(".pull-hint").getBoundingClientRect();
            const main = document.querySelector("main").getBoundingClientRect();
            return [hint.top + window.scrollY, hint.bottom + window.scrollY, hint.top - main.bottom, hint.height];
            """
        let found = try #require(try await evaluate(script, in: controller) as? [Double])
        let visibleTop = Double(scrollView.contentOffset.y + bars.top)
        let visibleBottom = Double(scrollView.contentOffset.y + scrollView.bounds.height - bars.bottom)
        #expect(found[3] > 0, "the hint has no height: \(found)")
        #expect(abs(found[2] - Double(FloatingSpacing.gap)) <= 0.5, "gap under the last message: \(found[2])")
        #expect(found[0] >= visibleTop - 0.5 && found[1] <= visibleBottom + 0.5,
                "hint \(found[0])...\(found[1]) out of the visible band \(visibleTop)...\(visibleBottom)")
    }

    /// A page shorter than the screen shows its end at once: the end-of-page bar is there without a scroll.
    @Test func aShortPageIsAtItsEndFromTheStart() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.obscuredInsets = bars
        let ends = recording(controller)
        controller.show(documentOf(height: 100, token: 1))
        #expect(await until { recorder.ready == [1] && ends.reports.last == true }, "reports: \(ends.reports)")
    }

    /// The page ends `FloatingSpacing.gap` above the bottom bar (operator, #820, 2026-11-16), not the old 2em; a page built
    /// without the pull (the post filter) has no hint.
    @Test func thePageEndsTheSharedGapAboveTheBarWithNoHintInTheFlow() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.show(documentOf(height: 100, token: 1, pullHint: false))
        #expect(await until { recorder.ready == [1] })
        let script = """
            return [getComputedStyle(document.body).paddingBottom, String(document.querySelectorAll(".pull-hint").length)];
            """
        let found = try #require(try await evaluate(script, in: controller) as? [String])
        #expect(found == ["\(Int(FloatingSpacing.gap))px", "0"])
    }
}
