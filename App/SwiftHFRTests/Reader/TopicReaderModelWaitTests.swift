import Foundation
import HFRModels
import HFRNetwork
@testable import SwiftHFR
import Testing

/// Issue #750: a topic opened again shows its messages, and "Chargement des messages" never spins forever.
@MainActor
struct TopicReaderModelWaitTests {
    private func model(_ pages: FakeTopicPages, clock: ReaderGate? = nil) -> TopicReaderModel {
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic), page: 1), title: "Sujet", source: pages)
        if let clock { reader.waitClock = { _ in await clock.wait() } }
        return reader
    }

    /// Lets the watch's task run after its clock fired, without real waiting.
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<1_000 where !condition() { await Task.yield() }
    }

    /// The reopen of #750: the same model (the topic stays selected) gets a new view, whose web view has not shown the page.
    /// The first view's ready must not count for it, or the screen shows a blank web view instead of waiting for it.
    @Test func aTopicOpenedAgainInANewViewIsNotShownUntilItsOwnWebViewIsReady() async {
        let pages = FakeTopicPages()
        let reader = model(pages)
        await reader.onAppear(viewer: 1)
        reader.documentDidBecomeReady(token: 1)
        #expect(reader.hasShownDocument)
        reader.viewDidDisappear(viewer: 1)
        await reader.onAppear(viewer: 2)
        #expect(!reader.hasShownDocument)
        reader.documentDidBecomeReady(token: 1)
        #expect(reader.hasShownDocument)
        #expect(pages.requests.count == 1)
    }

    /// The same view appearing again (rotation, tab back) keeps the page shown.
    @Test func theSameViewAppearingAgainKeepsThePageShown() async {
        let reader = model(FakeTopicPages())
        await reader.onAppear(viewer: 1)
        reader.documentDidBecomeReady(token: 1)
        await reader.onAppear(viewer: 1)
        #expect(reader.hasShownDocument)
    }

    /// The limit is HFRNetwork's own for a topic page request.
    @Test func theWaitLimitIsTheTopicPageRequestTimeout() {
        #expect(TopicReaderModel.waitLimit == .seconds(RequestTimeout.standard))
        #expect(TopicReaderModel.waitLimit == .seconds(30))
    }

    /// A fetch that never answers: on the limit, the load stops and the screen offers "Réessayer".
    @Test func aFetchThatNeverEndsTurnsIntoATimeoutWithRetry() async {
        let pages = FakeTopicPages()
        let fetch = ReaderGate()
        let clock = ReaderGate()
        pages.handler = { target in await fetch.wait(); return readerPage(page: target.page) }
        let reader = model(pages, clock: clock)
        let opening = Task { await reader.onAppear(viewer: 1) }
        await fetch.untilArrived()
        await clock.untilArrived()
        await clock.open()
        await settle { reader.error != nil }
        #expect(reader.error == .timedOut)
        #expect(!reader.isLoading)
        #expect(reader.page == nil)
        await fetch.open()
        await opening.value
        #expect(reader.page == nil, "the timed-out load delivered")
        reader.waitClock = { _ in try await Task.sleep(for: .seconds(3_600)) } // the next wait's watch must not fire
        await reader.retry()
        #expect(reader.error == nil)
        #expect(reader.page?.currentPage == 1)
    }

    /// A page the web view never shows: on the limit, "Réessayer"; a ready that still comes shows the page.
    @Test func aDocumentNeverReadyTurnsIntoATimeoutThatALateReadyClears() async {
        let clock = ReaderGate()
        let reader = model(FakeTopicPages(), clock: clock)
        await reader.onAppear(viewer: 1)
        #expect(reader.document?.token == 1)
        await clock.untilArrived()
        await clock.open()
        await settle { reader.error != nil }
        #expect(reader.error == .timedOut)
        #expect(!reader.hasShownDocument)
        reader.documentDidBecomeReady(token: 1)
        #expect(reader.error == nil)
        #expect(reader.hasShownDocument)
    }

    /// A page shown before the limit: the watch ends with the wait and changes nothing.
    @Test func aPageShownInTimeIsNotTimedOut() async {
        let clock = ReaderGate()
        let reader = model(FakeTopicPages(), clock: clock)
        await reader.onAppear(viewer: 1)
        await clock.untilArrived()
        reader.documentDidBecomeReady(token: 1)
        await clock.open()
        for _ in 0..<100 { await Task.yield() }
        #expect(reader.error == nil)
        #expect(reader.hasShownDocument)
    }

    /// #643's sequence: the load is cancelled by a disappearance and nothing restarts it. The wait still ends on the limit,
    /// and the screen coming back loads again rather than keeping the timeout.
    @Test func aStalledLoadTimesOutAndTheScreenComingBackLoadsAgain() async {
        let pages = FakeTopicPages()
        let fetch = ReaderGate()
        let clock = ReaderGate()
        pages.handler = { target in await fetch.wait(); return readerPage(page: target.page) }
        let reader = model(pages, clock: clock)
        let opening = Task { await reader.onAppear(viewer: 1) }
        await fetch.untilArrived()
        reader.viewDidDisappear(viewer: 1)
        await clock.untilArrived()
        await clock.open()
        await settle { reader.error != nil }
        #expect(reader.error == .timedOut)
        await fetch.open()
        await opening.value
        reader.waitClock = { _ in try await Task.sleep(for: .seconds(3_600)) } // the next wait's watch must not fire
        await reader.onAppear(viewer: 1)
        #expect(reader.error == nil)
        #expect(reader.page?.currentPage == 1)
        #expect(pages.requests.count == 2)
    }
}
