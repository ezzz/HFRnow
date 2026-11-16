@testable import SwiftHFR
import Testing
import UIKit

/// The wait for WebKit's reset of a new document's scroll view (#772), on a plain scroll view: no page and no WebKit, so the
/// reset is a `contentOffset` the test sets.
@MainActor
struct WebKitResetWatchTests {
    /// A scroll view under 100 points of bars, at `offset` (900: the previous document's, read 1000 points down).
    private func scrollView(offset: CGFloat) -> UIScrollView {
        let view = UIScrollView(frame: CGRect(x: 0, y: 0, width: 390, height: 800))
        view.contentSize = CGSize(width: 390, height: 10_000)
        view.contentInset = UIEdgeInsets(top: 100, left: 0, bottom: 50, right: 0)
        view.contentOffset = CGPoint(x: 0, y: offset)
        return view
    }

    private let top = CGPoint(x: 0, y: -100)

    /// Lets the main-actor task the watch queues at the reset run: tasks queued before these run before them.
    private func drain() async {
        for _ in 0..<3 { await Task { @MainActor in }.value }
    }

    @Test func aScrollViewAwayFromItsTopHoldsTheActionUntilTheResetThenRunsItOnce() async {
        let watch = WebKitResetWatch()
        let view = scrollView(offset: 900)
        let runs = Runs()
        watch.start(token: 1, on: view)
        watch.perform(token: 1, on: view) { runs.record() }
        await drain()
        #expect(runs.all.isEmpty, "the action ran before the reset")
        view.contentOffset = CGPoint(x: 0, y: 400)
        await drain()
        #expect(runs.all.isEmpty, "a move that is not the reset ran the action")
        view.contentOffset = top
        await drain()
        #expect(runs.all.count == 1)
        #expect(watch.token == nil)
        // The reset comes once: the scroll view reaching its top again later is the reader's.
        view.contentOffset = CGPoint(x: 0, y: 600)
        view.contentOffset = top
        await drain()
        #expect(runs.all.count == 1)
    }

    @Test func anActionAfterTheResetRunsAtOnce() async {
        let watch = WebKitResetWatch()
        let view = scrollView(offset: 900)
        let runs = Runs()
        watch.start(token: 1, on: view)
        view.contentOffset = top
        watch.perform(token: 1, on: view) { runs.record() }
        #expect(runs.all.count == 1)
    }

    @Test func aDragBeforeTheResetDropsTheAction() async {
        let watch = WebKitResetWatch()
        let view = scrollView(offset: 900)
        let runs = Runs()
        watch.start(token: 1, on: view)
        watch.perform(token: 1, on: view) { runs.record() }
        watch.userScrolls = { _ in true }
        view.contentOffset = CGPoint(x: 0, y: 700)
        #expect(watch.token == nil, "a drag left the watch armed")
        watch.userScrolls = { _ in false }
        view.contentOffset = top
        await drain()
        #expect(runs.all.isEmpty, "the reader's scroll to the top was taken for the reset")
    }

    @Test func aCommitWhileTheReaderScrollsWatchesNothing() {
        let watch = WebKitResetWatch()
        let view = scrollView(offset: 900)
        let runs = Runs()
        watch.userScrolls = { _ in true }
        watch.start(token: 1, on: view)
        #expect(watch.token == nil)
        watch.perform(token: 1, on: view) { runs.record() }
        #expect(runs.all.count == 1)
    }

    @Test func anotherDocumentDropsTheActionEvenOnceQueued() async {
        let watch = WebKitResetWatch()
        let held = scrollView(offset: 900)
        let runs = Runs()
        watch.start(token: 1, on: held)
        watch.perform(token: 1, on: held) { runs.record() }
        watch.stop()
        held.contentOffset = top
        await drain()
        #expect(runs.all.isEmpty, "a stopped watch ran its action")

        let queued = scrollView(offset: 900)
        watch.start(token: 2, on: queued)
        watch.perform(token: 2, on: queued) { runs.record() }
        queued.contentOffset = top // the reset: the action is queued for the next turn
        watch.stop() // and another document is shown before it runs
        await drain()
        #expect(runs.all.isEmpty, "an action queued at the reset ran after another document was shown")
    }

    /// A scroll view already at its top may have been reset without moving: the action runs at once and once more if the
    /// reset comes, until the page reports a reading position.
    @Test func atTheTopTheActionRunsAtOnceAndAgainAtALateReset() async {
        let watch = WebKitResetWatch()
        let view = scrollView(offset: -100)
        let runs = Runs()
        watch.start(token: 1, on: view)
        watch.perform(token: 1, on: view) { runs.record() }
        #expect(runs.all.count == 1)
        view.contentOffset = CGPoint(x: 0, y: 300)
        view.contentOffset = top
        await drain()
        #expect(runs.all.count == 2)
    }

    @Test func aPositionReportEndsTheSecondChance() async {
        let watch = WebKitResetWatch()
        let view = scrollView(offset: -100)
        let runs = Runs()
        watch.start(token: 1, on: view)
        watch.perform(token: 1, on: view) { runs.record() }
        watch.pageReportedPosition()
        #expect(watch.token == nil)
        view.contentOffset = CGPoint(x: 0, y: 300)
        view.contentOffset = top
        await drain()
        #expect(runs.all.count == 1, "a status-bar tap to the top after the reader read on ran the landing again")
    }
}

/// Counts the runs of a held action.
@MainActor
private final class Runs {
    private(set) var all: [Int] = []

    func record() { all.append(all.count + 1) }
}

/// The controller starts the watch at the shown document's commit and ends it when it shows another one (`show`).
@MainActor
@Suite(.serialized)
struct WebKitResetWatchControllerTests: ReaderWebTesting {
    /// The commit of the shown document's navigation starts the watch (`webView(_:didCommit:)`), whether or not the reset
    /// has already ended it by the time the page is ready.
    @Test func theCommitOfTheShownDocumentStartsTheWatch() async {
        let (controller, recorder) = makeController(transport: imageTransport())
        controller.show(document(token: 3))
        let watch = controller.resetWatch
        #expect(await until { watch.committedToken == 3 }, "committed: \(String(describing: watch.committedToken))")
        #expect(await until { recorder.ready == [3] })
        #expect(watch.committedToken == 3)
    }

    @Test func showingAnotherDocumentStopsTheWatch() {
        let (controller, _) = makeController(transport: imageTransport())
        controller.resetWatch.start(token: 99, on: controller.webView.scrollView)
        #expect(controller.resetWatch.token == 99)
        controller.show(document(token: 2))
        #expect(controller.resetWatch.token == nil)
        #expect(controller.resetWatch.committedToken == nil)
    }
}
