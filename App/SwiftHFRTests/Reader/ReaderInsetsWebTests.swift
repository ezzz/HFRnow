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

    /// Scrolls the page itself to `readingTop` (`scrollY`), then waits until the scroll view shows it below the bar: a native
    /// `setContentOffset` reaches the page's `scrollY` and scroll events asynchronously, and can be undone by a late layout.
    /// Waits `deadline`, so a CI log (durations, not messages) tells which step of a test failed.
    private func scrollPage(
        to readingTop: CGFloat, in controller: ReaderWebController, deadline: Duration
    ) async throws -> Bool {
        _ = try await evaluate("window.scrollTo(0, \(Double(readingTop))); return true;", in: controller)
        let scrollView = controller.webView.scrollView
        let top = controller.obscuredInsets.top
        return await until({ abs(scrollView.contentOffset.y + top - readingTop) <= 1 }, timeout: deadline)
    }

    @Test func theMessageHiddenUnderTheTopBarIsNotTheReadingPosition() async throws {
        let (controller, recorder) = makeController(transport: imageTransport())
        let reports = PositionReports()
        controller.events.position = { post, _ in reports.posts.append(post) }
        controller.obscuredInsets = bars
        controller.show(tallDocument(token: 1))
        #expect(await until { recorder.ready == [1] })
        #expect(await settled(controller))
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
        // The refresh starts with the banner, which goes away before the new document is ready.
        controller.show(tallDocument(token: 2, keepsScrollPosition: true))
        controller.obscuredInsets.top = 100
        #expect(await until({ recorder.ready == [1, 2] }, timeout: .seconds(90)), "ready: \(recorder.ready)")
        #expect(
            await until({ abs(scrollView.contentOffset.y - 900) <= 1 }, timeout: .seconds(30)), "offset: \(scrollView.contentOffset.y)"
        )
        // Still there once the document has finished loading (a late layout must not undo the restore).
        #expect(await settled(controller))
        #expect(abs(scrollView.contentOffset.y - 900) <= 1, "offset after load: \(scrollView.contentOffset.y)")
        #expect(abs(controller.readingTop - 1000) <= 1)
    }
}
