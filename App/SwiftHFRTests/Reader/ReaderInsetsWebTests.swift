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

    @Test func theMessageHiddenUnderTheTopBarIsNotTheReadingPosition() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        let reports = PositionReports()
        controller.events.position = { post, _ in reports.posts.append(post) }
        controller.obscuredInsets = bars
        controller.show(tallDocument(token: 1))
        #expect(await until { recorder.ready == [1] })
        #expect(await settled(controller))
        // Message 1 ends 90 points into the screen, under the 100-point bar: message 2 is the first one the reader sees.
        let second = try await top(of: 2, in: controller)
        controller.webView.scrollView.setContentOffset(CGPoint(x: 0, y: second - 90), animated: false)
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
        let scrollView = controller.webView.scrollView
        scrollView.setContentOffset(CGPoint(x: 0, y: 900), animated: false) // content 1000 at the bar's edge
        // A banner appears above the page: the content at the bars' edge stays.
        controller.obscuredInsets.top = 160
        #expect(scrollView.contentOffset.y == 840, "offset after the banner: \(scrollView.contentOffset.y)")
        #expect(controller.readingTop == 1000)
        // The page counts from the bars' edge too: what a refresh restores is where the reader is.
        let scrolled = try await evaluate("return window.scrollY;", in: controller) as? NSNumber
        #expect(abs((scrolled?.doubleValue ?? -1) - 1000) <= 1, "scrollY: \(String(describing: scrolled))")
        // The refresh starts with the banner, which goes away before the new document is ready.
        controller.show(tallDocument(token: 2, keepsScrollPosition: true))
        controller.obscuredInsets.top = 100
        // Distinct deadlines, so a CI log (which shows durations, not messages) tells which step failed.
        #expect(await until({ recorder.ready == [1, 2] }, timeout: .seconds(90)), "ready: \(recorder.ready)")
        #expect(
            await until({ abs(scrollView.contentOffset.y - 900) <= 1 }, timeout: .seconds(30)), "offset: \(scrollView.contentOffset.y)"
        )
        #expect(controller.readingTop == 1000)
    }
}
