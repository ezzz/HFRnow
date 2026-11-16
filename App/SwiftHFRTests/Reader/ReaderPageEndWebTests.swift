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
        let options = ReaderRenderOptions(showsMessageMenus: true, offersPullToRefresh: true)
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
        let scrollView = controller.webView.scrollView
        _ = try await evaluate("window.scrollTo(0, document.documentElement.scrollHeight); return true;", in: controller)
        #expect(await until { ends.reports.last == true }, "reports: \(ends.reports), offset \(scrollView.contentOffset)")
        _ = try await evaluate("window.scrollTo(0, 0); return true;", in: controller)
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

    @Test func thePageEndsWithThePullHintAndPostsCarryTheLegacyPlus() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.show(documentOf(height: 100, token: 1))
        #expect(await until { recorder.ready == [1] })
        let script = """
            const hint = document.querySelector("main + p.pull-hint");
            const button = document.querySelector("button.menu-button");
            return [hint ? hint.textContent : "", hint ? hint.getAttribute("aria-hidden") : "", button ? button.textContent : ""];
            """
        let found = try #require(try await evaluate(script, in: controller) as? [String])
        #expect(found == ["Tirer vers le haut pour actualiser", "true", "+"])
    }
}
