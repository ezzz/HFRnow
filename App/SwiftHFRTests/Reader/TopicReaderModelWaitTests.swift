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
        reader.waitClock = { _ in try await Task.sleep(for: .seconds(3_600)) } // the retry's own watch must not fire here
        await reader.retry()
        #expect(reader.error == nil)
        #expect(reader.page?.currentPage == 1)
    }

    /// Fable round 1, finding 2: "Réessayer" after a timeout waits again on the spinner, under a new watch, instead of
    /// keeping the timeout up while it loads.
    @Test func aRetryAfterATimeoutClearsItAndIsWatchedAgain() async throws {
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
        let retryFetch = ReaderGate()
        let retryClock = ReaderGate()
        pages.handler = { target in await retryFetch.wait(); return readerPage(page: target.page) }
        reader.waitClock = { _ in await retryClock.wait() }
        let retrying = Task { await reader.retry() }
        await retryFetch.untilArrived()
        #expect(reader.isLoading)
        // Required: without a watch on the retry, waiting for its clock below would never return.
        try #require(reader.error == nil, "the timeout stayed up while the retry loads")
        await retryClock.untilArrived() // the retry's wait is watched
        await retryClock.open()
        await settle { reader.error != nil }
        #expect(reader.error == .timedOut)
        await fetch.open()
        await retryFetch.open()
        await opening.value
        await retrying.value
    }

    /// Fable round 1, finding 1: a wait left before its page was shown is not timed out off screen. Opened again more than
    /// the limit later (the model kept by `NavigationModel.reader(for:)`), the topic waits for its new web view, with no
    /// stale timeout.
    @Test func aWaitLeftOffScreenIsNotATimeoutWhenTheTopicIsOpenedAgain() async {
        let clock = ReaderGate()
        let reader = model(FakeTopicPages(), clock: clock)
        await reader.onAppear(viewer: 1)
        #expect(reader.document?.token == 1)
        await clock.untilArrived()
        reader.viewDidDisappear(viewer: 1)
        await clock.open() // the limit passes while the topic is off screen
        for _ in 0..<100 { await Task.yield() }
        #expect(reader.error == nil)
        reader.waitClock = { _ in try await Task.sleep(for: .seconds(3_600)) }
        await reader.onAppear(viewer: 2)
        #expect(reader.error == nil)
        #expect(!reader.hasShownDocument)
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

    /// A screen still showing the spinner with no load running (a load stopped while its screen stayed, the #643 shape):
    /// the wait still ends on the limit, and the screen coming back loads again rather than keeping the timeout.
    @Test func aStalledLoadTimesOutAndTheScreenComingBackLoadsAgain() async {
        let pages = FakeTopicPages()
        let fetch = ReaderGate()
        let clock = ReaderGate()
        pages.handler = { target in await fetch.wait(); return readerPage(page: target.page) }
        let reader = model(pages, clock: clock)
        let opening = Task { await reader.onAppear(viewer: 1) }
        await fetch.untilArrived()
        reader.cancel() // stopped, the screen still there
        #expect(!reader.isLoading)
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

    /// #786 CI: `ReplyEntryTests` lost its reload after a reply when a run took over 30 s. A model no reader view shows has no
    /// web view to make its page ready, so its wait is never watched (the real clock of a test model fired mid-test).
    @Test func aReaderNoViewShowsIsNeverTimedOut() async {
        let reader = model(FakeTopicPages { target in readerPage(page: min(target.page, 5)) })
        reader.waitClock = { _ in } // the limit passes at once
        await reader.onAppear()
        for _ in 0..<200 { await Task.yield() }
        #expect(reader.error == nil)
        await reader.showLatestPost()
        for _ in 0..<200 { await Task.yield() }
        #expect(reader.error == nil)
        #expect(reader.page?.currentPage == 5)
    }

    /// A load started while the screen already waited (Actualiser, the latest post after a reply) gets the whole limit: the
    /// earlier wait's deadline must not cancel it.
    @Test func aLoadStartedLateInAWaitGetsTheWholeLimit() async {
        let pages = FakeTopicPages()
        let clock = ReaderGate()
        let reader = model(pages, clock: clock)
        await reader.onAppear(viewer: 1)
        #expect(reader.document?.token == 1)
        await clock.untilArrived()
        reader.waitClock = { _ in try await Task.sleep(for: .seconds(3_600)) }
        let fetch = ReaderGate()
        pages.handler = { target in await fetch.wait(); return readerPage(page: target.page) }
        let refreshing = Task { await reader.refresh() }
        await fetch.untilArrived()
        await clock.open() // the first wait's limit passes while the refresh loads
        for _ in 0..<200 { await Task.yield() }
        #expect(reader.error == nil)
        #expect(reader.isLoading)
        await fetch.open()
        await refreshing.value
        #expect(reader.document?.token == 2)
        #expect(reader.error == nil)
    }
}
