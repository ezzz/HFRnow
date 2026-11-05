import Foundation
import HFRClient
import HFRModels
import HFRParsing
import HFRStorage
@testable import SwiftHFR
import Testing

/// A scripted post filter source: each batch request is answered by a closure and recorded.
final class FakeFilteredSource: FilteredPostsSource, @unchecked Sendable {
    typealias Handler = @Sendable (Int, Int?, @escaping @Sendable (FilteredPostsProgress) async -> Void) async throws(FilteredPostsError)
        -> FilteredPostsBatch

    struct Call: Equatable {
        let topic: TopicID
        let page: Int
        let after: Int?
        let criteria: FilteredPostsCriteria
    }

    private let lock = NSLock()
    private var recorded: [Call] = []
    private var storedHandler: Handler

    init(handler: @escaping Handler) { storedHandler = handler }

    var handler: Handler {
        get { lock.withLock { storedHandler } }
        set { lock.withLock { storedHandler = newValue } }
    }

    var calls: [Call] { lock.withLock { recorded } }

    func batch(
        in topic: TopicID, from page: Int, after message: Int?, criteria: FilteredPostsCriteria,
        progress: @escaping @Sendable (FilteredPostsProgress) async -> Void
    ) async throws(FilteredPostsError) -> FilteredPostsBatch {
        lock.withLock { recorded.append(Call(topic: topic, page: page, after: message, criteria: criteria)) }
        return try await handler(page, message, progress)
    }
}

let filterTopic = TopicID(category: .forum(13), topic: 28563)

/// A batch of `posts` messages (numbered from `page * 100`) read from `start` to `end`.
func filteredBatch(start: Int, end: Int, posts: Int = 2, maxPage: Int = 9, finished: Bool = false) -> FilteredPostsBatch {
    let kept = (0..<posts).map { index in
        FilteredPost(
            page: start,
            block: MessageBlock(numreponse: start * 100 + index, author: "auteur", dateText: "27-10-2026", contentHTML: "<p>x</p>"),
            quotes: []
        )
    }
    return FilteredPostsBatch(posts: kept, startPage: start, endPage: end, maxPage: maxPage, isFinished: finished)
}

/// A normalizer that holds the batch until the test releases it.
final class BlockingNormalizer: MessageContentNormalizing, @unchecked Sendable {
    let entered = DispatchSemaphore(value: 0)
    let release = DispatchSemaphore(value: 0)

    func normalize(contentHTML: String, pageURL: URL) throws(ParsingError) -> MessageContent {
        entered.signal()
        release.wait()
        return MessageContent(html: contentHTML)
    }
}

@MainActor @Suite(.timeLimit(.minutes(1)))
struct FilteredPostsModelTests {
    private struct PassNormalizer: MessageContentNormalizing {
        func normalize(contentHTML: String, pageURL: URL) throws(ParsingError) -> MessageContent {
            MessageContent(html: contentHTML)
        }
    }

    private func model(_ source: FakeFilteredSource, criteria: FilteredPostsCriteria = FilteredPostsCriteria()) -> FilteredPostsModel {
        FilteredPostsModel(services: FilteredPostsServices(source: source, criteria: { criteria }, normalizer: PassNormalizer()))
    }

    private func settle(_ model: FilteredPostsModel) async {
        while model.isRunning || model.isAdvancing { await Task.yield() }
    }

    @Test func aRunShowsTheBatchWithLegacysSubtitleAndAsksForTheCriteriaOfTheSettings() async {
        let criteria = FilteredPostsCriteria(minimumQuoteCount: 5, pseudo: "moi", allowlist: ["ami"], includesAllowlist: false)
        let source = FakeFilteredSource { _, _, _ in filteredBatch(start: 3, end: 4, posts: 3) }
        let model = model(source, criteria: criteria)
        model.start(topic: filterTopic, title: "Sujet", page: 3, after: 77)
        #expect(model.isRunning)
        await settle(model)
        #expect(source.calls == [.init(topic: filterTopic, page: 3, after: 77, criteria: criteria)])
        #expect(model.result?.subtitle == "3 posts | 3 à 4")
        #expect(model.result?.page.messages.map(\.numreponse) == [300, 301, 302])
        #expect(model.result?.page.currentPage == 4)
        #expect(model.progress == nil)
        #expect(model.errorMessage == nil)
    }

    @Test func aSinglePageBatchSaysOnePage() async {
        let model = model(FakeFilteredSource { _, _, _ in filteredBatch(start: 3, end: 3, posts: 1) })
        model.start(topic: filterTopic, title: "Sujet", page: 3, after: nil)
        await settle(model)
        #expect(model.result?.subtitle == "1 post | 3")
    }

    @Test func progressIsShownWhileTheRunReadsPagesAndReadsLikeLegacy() async {
        let gate = ReaderGate()
        let source = FakeFilteredSource { _, _, progress in
            await progress(FilteredPostsProgress(page: 4, maxPage: 9, resultCount: 12))
            await gate.wait()
            return filteredBatch(start: 3, end: 4)
        }
        let model = model(source)
        model.start(topic: filterTopic, title: "Sujet", page: 3, after: nil)
        await gate.untilArrived()
        #expect(model.progress == FilteredPostsProgress(page: 4, maxPage: 9, resultCount: 12))
        #expect(model.bannerText == "12 posts | page 4/9")
        await gate.open()
        await settle(model)
        #expect(model.bannerText == nil)
    }

    @Test func aRunThatKeepsNothingSaysSoAndShowsNoResult() async {
        let model = model(FakeFilteredSource { _, _, _ in filteredBatch(start: 3, end: 5, posts: 0) })
        model.start(topic: filterTopic, title: "Sujet", page: 3, after: nil)
        await settle(model)
        #expect(model.result == nil)
        #expect(model.statusMessage == "Aucun post n'a été trouvé")
        model.dismissStatus()
        #expect(model.bannerText == nil)
    }

    @Test func cancellingAFirstRunShowsNothingAndNoError() async {
        let gate = ReaderGate()
        let source = FakeFilteredSource { _, _, _ in
            await gate.wait()
            return filteredBatch(start: 1, end: 1)
        }
        let model = model(source)
        model.start(topic: filterTopic, title: "Sujet", page: 1, after: nil)
        await gate.untilArrived()
        model.cancel()
        let stale = model.lastRun
        await gate.open()
        await stale?.value
        #expect(!model.isRunning)
        #expect(model.result == nil)
        #expect(model.errorMessage == nil)
        #expect(model.statusMessage == nil)
    }

    @Test func aRunCancelledWhileItsBatchIsBeingNormalizedNeverDelivers() async {
        let blocking = BlockingNormalizer()
        let services = FilteredPostsServices(
            source: FakeFilteredSource { _, _, _ in filteredBatch(start: 1, end: 1, posts: 1) },
            criteria: { FilteredPostsCriteria() }, normalizer: blocking
        )
        let model = FilteredPostsModel(services: services)
        model.start(topic: filterTopic, title: "Sujet", page: 1, after: nil)
        // The run needs the main actor to start: wait for the normalizer from another thread, not this one.
        await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                blocking.entered.wait()
                continuation.resume()
            }
        }
        let stale = model.lastRun
        model.cancel()
        blocking.release.signal()
        await stale?.value
        #expect(model.result == nil)
        #expect(model.statusMessage == nil)
        #expect(!model.isBusy)
    }

    @Test func aSecondStartWhileRunningIsIgnored() async {
        let gate = ReaderGate()
        let source = FakeFilteredSource { _, _, _ in
            await gate.wait()
            return filteredBatch(start: 1, end: 1)
        }
        let model = model(source)
        model.start(topic: filterTopic, title: "Sujet", page: 1, after: nil)
        await gate.untilArrived()
        model.start(topic: filterTopic, title: "Autre", page: 5, after: nil)
        await gate.open()
        await settle(model)
        #expect(source.calls.map(\.page) == [1])
        #expect(model.title == "Sujet")
    }

    @Test func aFailureIsShownInFrenchAndDismissed() async {
        let model = model(FakeFilteredSource { _, _, _ throws(FilteredPostsError) in throw .network(.offline) })
        model.start(topic: filterTopic, title: "Sujet", page: 1, after: nil)
        await settle(model)
        #expect(model.errorMessage == "Pas de connexion. Réessayez une fois connecté.")
        #expect(model.result == nil)
        model.dismissError()
        #expect(model.errorMessage == nil)
    }

    // MARK: - Résultats suivants

    @Test func nextResultsStartAfterTheLastPageReadAndReplaceTheBatch() async {
        let source = FakeFilteredSource { page, _, _ in
            page == 3 ? filteredBatch(start: 3, end: 4) : filteredBatch(start: 5, end: 7, posts: 1)
        }
        let model = model(source)
        model.start(topic: filterTopic, title: "Sujet", page: 3, after: 10)
        await settle(model)
        #expect(model.nextBatchHint == "Lit les pages suivantes à partir de la page 5 et affiche les prochains posts retenus.")
        model.showNextBatch()
        #expect(model.isAdvancing)
        await settle(model)
        #expect(source.calls.map(\.page) == [3, 5])
        #expect(source.calls.last?.after == nil)
        #expect(model.result?.subtitle == "1 post | 5 à 7")
    }

    @Test func nextResultsWithNothingLeftMarkTheTopicFinished() async {
        let source = FakeFilteredSource { page, _, _ in
            page == 3 ? filteredBatch(start: 3, end: 4) : filteredBatch(start: 5, end: 9, posts: 0, finished: true)
        }
        let model = model(source)
        model.start(topic: filterTopic, title: "Sujet", page: 3, after: nil)
        await settle(model)
        model.showNextBatch()
        await settle(model)
        #expect(model.result?.isFinished == true)
        #expect(model.result?.count == 2)
        #expect(model.statusMessage == "Aucun autre post trouvé")
        #expect(model.nextBatchHint == nil)
        model.showNextBatch()
        #expect(source.calls.count == 2)
    }

    @Test func aFinishedTopicOffersNoNextResults() async {
        let source = FakeFilteredSource { _, _, _ in filteredBatch(start: 8, end: 9, finished: true) }
        let model = model(source)
        model.start(topic: filterTopic, title: "Sujet", page: 8, after: nil)
        await settle(model)
        model.showNextBatch()
        #expect(!model.isAdvancing)
        #expect(source.calls.count == 1)
    }

    @Test func cancellingNextResultsLeavesTheBatchShown() async {
        let gate = ReaderGate()
        let source = FakeFilteredSource { page, _, _ in
            if page != 3 { await gate.wait() }
            return filteredBatch(start: page, end: page + 1)
        }
        let model = model(source)
        model.start(topic: filterTopic, title: "Sujet", page: 3, after: nil)
        await settle(model)
        let shown = model.result
        model.showNextBatch()
        await gate.untilArrived()
        model.cancel()
        let stale = model.lastRun
        await gate.open()
        await stale?.value
        #expect(!model.isAdvancing)
        #expect(model.result == shown)
        #expect(model.errorMessage == nil)
    }

    @Test func aFailureOfNextResultsLeavesTheBatchShownAndAllowsAnotherTry() async {
        let failing = LockedFlag()
        let source = FakeFilteredSource { page, _, _ throws(FilteredPostsError) in
            if page != 3, failing.value { throw .network(.timedOut) }
            return filteredBatch(start: page, end: page)
        }
        failing.value = true
        let model = model(source)
        model.start(topic: filterTopic, title: "Sujet", page: 3, after: nil)
        await settle(model)
        model.showNextBatch()
        await settle(model)
        #expect(model.result?.subtitle == "2 posts | 3")
        #expect(model.errorMessage == "Le forum n'a pas répondu à temps.")
        failing.value = false
        model.showNextBatch()
        await settle(model)
        #expect(model.result?.subtitle == "2 posts | 4")
        #expect(model.errorMessage == nil)
    }

    @Test func closingTheResultStopsTheRunAndForgetsTheBatch() async {
        let gate = ReaderGate()
        let source = FakeFilteredSource { page, _, _ in
            if page != 3 { await gate.wait() }
            return filteredBatch(start: page, end: page)
        }
        let model = model(source)
        model.start(topic: filterTopic, title: "Sujet", page: 3, after: nil)
        await settle(model)
        model.showNextBatch()
        await gate.untilArrived()
        model.closeResult()
        let stale = model.lastRun
        await gate.open()
        await stale?.value
        #expect(model.result == nil)
        #expect(!model.isAdvancing)
    }
}

/// A flag a scripted handler reads from another task.
final class LockedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = false
    var value: Bool {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}
