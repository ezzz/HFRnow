import Foundation
import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Testing

/// LOT-139: what is fetched to be saved, and how a save ends. Pages are the LOT-001 captures.
@MainActor
struct OfflineSaveTests {
    private static let canonical = "https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm"

    private static func response(_ file: String, url: String) throws -> HTTPResponse {
        HTTPResponse(
            statusCode: 200, headers: ["Content-Type": "text/html; charset=utf-8"], url: try #require(URL(string: url)),
            body: try LiveTopicPageSourceTests.capture(file)
        )
    }

    private static func model(
        _ cache: OfflineTempCache, onStart: @escaping @Sendable () -> Void = {}, fetcher: FakeOfflineFetcher
    ) -> OfflineSaveModel {
        OfflineSaveModel(store: LiveOfflineStore(store: OfflineTopicStore(cache: cache.cache), onStart: onStart), fetcher: fetcher)
    }

    // MARK: - Fetching without the session

    @Test func pagesAreFetchedWithoutTheSessionWhateverThePage() async throws {
        let body = try Self.response("R20-topic-p1-anon.html", url: Self.canonical)
        let session = MockTransport { _ in body }
        let anonymous = MockTransport { _ in body }
        let fetcher = LiveOfflinePageFetcher(
            fetcher: PageFetcher(session: session, anonymous: anonymous), normalizer: LiveContentNormalizer()
        )
        let fetched = try await fetcher.fetch(topic: OfflineCorpus.pizza, page: 1)
        #expect(fetched.page == 1)
        #expect(await session.requests.isEmpty)
        #expect(await anonymous.requests.count == 1)
    }

    @Test func aPageThatIsNotATopicPageIsNeverHandedOn() async throws {
        // The login form HFR serves (W00) is a real page without any message: the store would keep it as the topic's page.
        let body = try Self.response("W00-login-form-anon.html", url: Self.canonical)
        let anonymous = MockTransport { _ in body }
        let fetcher = LiveOfflinePageFetcher(
            fetcher: PageFetcher(session: MockTransport(replies: []), anonymous: anonymous), normalizer: LiveContentNormalizer()
        )
        await #expect(throws: ListLoadError.unreadable) { try await fetcher.fetch(topic: OfflineCorpus.pizza, page: 1) }
    }

    @Test func theServedPageNumberFilesThePage() async throws {
        // R24: page 2202 asked, HFR serves 2201.
        let served = "https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_2201.htm"
        let body = try Self.response("R24-topic-beyond-last-page-anon.html", url: served)
        let fetcher = LiveOfflinePageFetcher(
            fetcher: PageFetcher(session: MockTransport(replies: []), anonymous: MockTransport { _ in body }),
            normalizer: LiveContentNormalizer()
        )
        #expect(try await fetcher.fetch(topic: OfflineCorpus.pizza, page: 2202).page == 2201)
    }

    // MARK: - Saving

    @Test func savesTheRequestedPagesInOrderAndStopsAtTheFirstFailure() async throws {
        let cache = try OfflineTempCache()
        defer { cache.cleanUp() }
        let html = try OfflineCorpus.html("R20-topic-p1-anon.html")
        let fetcher = FakeOfflineFetcher { page throws(ListLoadError) in
            if page == 3 { throw .timedOut }
            return FetchedOfflinePage(html: html, page: page)
        }
        let saver = Self.model(cache, fetcher: fetcher)
        await saver.save(topic: OfflineCorpus.pizza, title: "Pizza maison", pages: 1...4)
        #expect(saver.state == .failed(message: ListLoadError.timedOut.detail, saved: 2))
        #expect(fetcher.requests == [1, 2, 3])
        let topics = try OfflineTopicStore(cache: cache.cache).topics()
        #expect(topics.map(\.pages) == [[1, 2]])
        #expect(topics.first?.title == "Pizza maison")
    }

    @Test func aPageFetchedWithTheSessionIsRefusedWithItsReason() async throws {
        let cache = try OfflineTempCache()
        defer { cache.cleanUp() }
        let loggedIn = try OfflineCorpus.html("R21-topic-p1-logged-in.html")
        let saver = Self.model(cache, fetcher: FakeOfflineFetcher { FetchedOfflinePage(html: loggedIn, page: $0) })
        await saver.save(topic: OfflineCorpus.pizza, title: "Pizza maison", pages: 1...1)
        #expect(saver.state == .failed(message: "Page non enregistrable : elle contient des données de session.", saved: 0))
        #expect(try OfflineTopicStore(cache: cache.cache).topics().isEmpty)
    }

    @Test func finishedSaveCountsItsPagesAndDismissesToIdle() async throws {
        let cache = try OfflineTempCache()
        defer { cache.cleanUp() }
        let html = try OfflineCorpus.html("R22a-topic-middle-page-anon.html")
        let saver = Self.model(cache, fetcher: FakeOfflineFetcher { FetchedOfflinePage(html: html, page: $0) })
        await saver.save(topic: OfflineCorpus.pizza, title: "t", pages: 1100...1102)
        #expect(saver.state == .finished(saved: 3))
        #expect(OfflineSaveText.text(for: saver.state) == "3 pages enregistrées hors ligne")
        saver.dismiss()
        #expect(saver.state == .idle)
    }

    @Test func aSaveStoppedByTheMemberKeepsWhatWasSaved() async throws {
        let cache = try OfflineTempCache()
        defer { cache.cleanUp() }
        let html = try OfflineCorpus.html("R22a-topic-middle-page-anon.html")
        let gate = ReaderGate()
        let fetcher = FakeOfflineFetcher { page throws(ListLoadError) in
            FetchedOfflinePage(html: html, page: page)
        }
        let saver = OfflineSaveModel(
            store: GatedStore(base: LiveOfflineStore(store: OfflineTopicStore(cache: cache.cache)), gate: gate, onPage: 2), fetcher: fetcher
        )
        let run = Task { await saver.save(topic: OfflineCorpus.pizza, title: "t", pages: 1...5) }
        await gate.untilArrived()
        saver.cancel()
        await gate.open()
        await run.value
        #expect(saver.state == .stopped(saved: 2))
        #expect(try OfflineTopicStore(cache: cache.cache).topics().first?.pages == [1, 2])
    }

    // MARK: - Off the main actor

    @Test func theStoreRunsOffTheMainThread() async throws {
        let cache = try OfflineTempCache()
        defer { cache.cleanUp() }
        let ranOnMain = Locked(false)
        let store = LiveOfflineStore(store: OfflineTopicStore(cache: cache.cache), onStart: {
            if Thread.isMainThread { ranOnMain.set(true) }
        })
        let page = OfflinePage(
            topic: OfflineCorpus.pizza, page: 1, title: "t", html: try OfflineCorpus.html("R20-topic-p1-anon.html"), savedAt: .now
        )
        // Called from the main actor, as the models do.
        try await store.save(page)
        _ = try await store.topics()
        _ = try await store.page(1, of: OfflineCorpus.pizza)
        _ = await store.sizeOnDisk()
        try await store.remove(OfflineCorpus.pizza)
        #expect(!ranOnMain.value)
    }
}

/// A mutable flag a `@Sendable` closure can set.
final class Locked<Value: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: Value
    init(_ value: Value) { stored = value }
    var value: Value { lock.withLock { stored } }
    func set(_ value: Value) { lock.withLock { stored = value } }
}

/// A store that holds the save of `onPage` until the test lets it go.
struct GatedStore: OfflineStoring {
    let base: LiveOfflineStore
    let gate: ReaderGate
    let onPage: Int

    func save(_ page: OfflinePage) async throws(OfflineStoreError) {
        if page.page == onPage { await gate.wait() }
        try await base.save(page)
    }
    func topics() async throws(OfflineStoreError) -> [OfflineTopic] { try await base.topics() }
    func page(_ number: Int, of topic: TopicID) async throws(OfflineStoreError) -> OfflinePage? { try await base.page(number, of: topic) }
    func remove(_ topic: TopicID) async throws(OfflineStoreError) { try await base.remove(topic) }
    func removeAll() async throws(OfflineStoreError) { try await base.removeAll() }
    func sizeOnDisk() async -> Int { await base.sizeOnDisk() }
}
