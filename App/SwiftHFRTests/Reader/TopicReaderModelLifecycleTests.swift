import Foundation
import HFRModels
@testable import SwiftHFR
import Testing

/// Issue #566: the reader never stays on "Chargement des messages" with no page, no load and no error, while a cancelled
/// load still never delivers (#108).
@MainActor
struct TopicReaderModelLifecycleTests {
    private func model(_ pages: FakeTopicPages) -> TopicReaderModel {
        TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic), page: 1), title: "Sujet", source: pages)
    }

    /// Issue #566 (H1b): a replacement view appears on the same model while the first view's load runs, then the first view
    /// goes away. Its disappearance must not stop the load the new view waits for: a page or an error, never idle.
    @Test func anOldViewGoingAwayDoesNotStopTheLoadOfTheViewThatReplacedIt() async {
        let pages = FakeTopicPages()
        let reader = model(pages)
        let gate = ReaderGate()
        pages.handler = { target in await gate.wait(); return readerPage(page: target.page) }
        let first = Task { await reader.onAppear(viewer: 1) }
        await gate.untilArrived()
        await reader.onAppear(viewer: 2)
        reader.viewDidDisappear(viewer: 1)
        await gate.open()
        await first.value
        #expect(reader.page != nil || reader.error != nil, "left idle: no page, no load, no error")
        #expect(reader.page?.currentPage == 1)
        #expect(pages.requests.count == 1)
    }

    /// The view that appeared last going away stops the load (#108), and the next appearance loads again (issue #566).
    @Test func theCurrentViewGoingAwayStopsTheLoadAndItsReturnLoadsAgain() async {
        let pages = FakeTopicPages()
        let reader = model(pages)
        let gate = ReaderGate()
        pages.handler = { target in await gate.wait(); return readerPage(page: target.page) }
        let first = Task { await reader.onAppear(viewer: 1) }
        await gate.untilArrived()
        reader.viewDidDisappear(viewer: 1)
        await gate.open()
        await first.value
        #expect(reader.page == nil)
        #expect(reader.document == nil)
        #expect(!reader.isLoading)
        await reader.onAppear(viewer: 1)
        #expect(reader.page?.currentPage == 1)
        #expect(pages.requests.count == 2)
    }

    /// Issue #566 (H3): the transport reports a cancellation nobody asked for. The reader asks once more, and never stays
    /// with no page, no load and no error.
    @Test func anUnrequestedCancellationIsAskedAgainOnce() async {
        let pages = FakeTopicPages()
        let reader = model(pages)
        let calls = ReaderCallCounter()
        pages.handler = { (target) async throws(ListLoadError) -> ReaderPage in
            if calls.next() == 1 { throw .cancelled }
            return readerPage(page: target.page)
        }
        await reader.onAppear()
        #expect(reader.page?.currentPage == 1)
        #expect(reader.error == nil)
        #expect(pages.requests.count == 2)
    }

    @Test func aRepeatedUnrequestedCancellationIsAnError() async {
        let pages = FakeTopicPages()
        let reader = model(pages)
        pages.handler = { (_) async throws(ListLoadError) -> ReaderPage in throw .cancelled }
        await reader.onAppear()
        #expect(reader.page == nil)
        #expect(!reader.isLoading)
        #expect(reader.error == .other)
        #expect(pages.requests.count == 2)
    }

    /// Issue #566 (H2): the web view could not show the current document: an error to retry, not a spinner.
    @Test func aDocumentTheWebViewCouldNotShowIsAnError() async {
        let pages = FakeTopicPages()
        let reader = model(pages)
        await reader.onAppear()
        await reader.goToPage(2)
        reader.documentDidFail(token: 1)
        #expect(reader.error == nil)
        reader.documentDidFail(token: 2)
        #expect(reader.error == .other)
        await reader.retry()
        #expect(reader.error == nil)
        #expect(reader.document?.token == 3)
    }
}
