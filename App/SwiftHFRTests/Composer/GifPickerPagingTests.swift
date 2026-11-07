import Foundation
import HFRNetwork
@testable import SwiftHFR
import Testing

/// LOT-155: paging, the end of the list, failures and answers that arrive after the list changed.
@MainActor
struct GifPickerPagingTests {
    @Test func nextPageAsksTheNextOffsetAndAPageOfRepeatsEndsTheList() async throws {
        let (transport, client) = try GifTestSupport.giphy()
        let (model, _) = GifTestSupport.model(client, accepted: true)
        await model.start()
        let first = model.items

        await model.loadMore()
        let queries = await transport.requests.map { $0.url.query() ?? "" }
        #expect(queries.count == 2)
        #expect(queries[1].contains("offset=25"))
        // The capture answers the same three GIFs again: nothing is added, and that page ends the list.
        #expect(model.items == first)
        #expect(!model.moreFailed)

        await model.loadMore()
        #expect(await transport.requests.count == 2)
    }

    @Test func theListEndsWhenTheOffsetReachesTheTotal() async throws {
        let (transport, client) = try GifTestSupport.giphy(.init(edit: { json in
            var pagination = json["pagination"] as? [String: Any] ?? [:]
            pagination["total_count"] = GiphyClient.defaultLimit
            json["pagination"] = pagination
        }))
        let (model, _) = GifTestSupport.model(client, accepted: true)

        await model.start()
        await model.loadMore()

        #expect(await transport.requests.count == 1)
    }

    @Test func anEmptyPageEndsTheList() async throws {
        let (transport, client) = try GifTestSupport.giphy(.init(empty: [1]))
        let (model, _) = GifTestSupport.model(client, accepted: true)
        await model.start()

        await model.loadMore()
        await model.loadMore()

        #expect(await transport.requests.count == 2)
        #expect(model.items.count == 3)
    }

    @Test func aFailedFirstPageSaysWhyAndRetryRecovers() async throws {
        let (_, client) = try GifTestSupport.giphy(.init(failing: [0]))
        let (model, _) = GifTestSupport.model(client, accepted: true)

        await model.start()
        #expect(model.phase == .failed(GifPickerModel.message(for: .network(.offline))))
        #expect(model.items.isEmpty)

        await model.retry()
        #expect(model.phase == .loaded)
        #expect(model.items.count == 3)
    }

    @Test func aFailedNextPageKeepsTheListAndOffersARetry() async throws {
        let (_, client) = try GifTestSupport.giphy(.init(failing: [1]))
        let (model, _) = GifTestSupport.model(client, accepted: true)
        await model.start()
        let first = model.items

        await model.loadMore()
        #expect(model.moreFailed)
        #expect(model.phase == .loaded)
        #expect(model.items == first)

        await model.loadMore()
        #expect(!model.moreFailed)
    }

    @Test func reachingTheEndOfAFailedListDoesNotRetryByItself() async throws {
        let (transport, client) = try GifTestSupport.giphy(.init(failing: [1]))
        let (model, _) = GifTestSupport.model(client, accepted: true)
        await model.start()
        await model.loadMore()
        let last = try #require(model.items.last)

        await model.loadMoreIfNeeded(after: last)

        #expect(model.moreFailed)
        #expect(await transport.requests.count == 2)
    }

    @Test func aFirstPageArrivingAfterANewSearchIsDropped() async throws {
        let gate = ReaderGate()
        let (_, client) = try GifTestSupport.giphy(.init(gates: [0: gate]))
        let (model, _) = GifTestSupport.model(client, accepted: true)
        let trending = Task { await model.start() }
        await gate.untilArrived()

        model.query = "hello"
        await model.submitSearch()
        await gate.open()
        await trending.value

        #expect(model.activeQuery == "hello")
        #expect(model.phase == .loaded)
        #expect(model.items.count == 3)
        #expect(model.items.first?.id == GifTestSupport.firstSearchID)
    }

    @Test func aNextPageArrivingAfterANewSearchIsDropped() async throws {
        let gate = ReaderGate()
        let (_, client) = try GifTestSupport.giphy(.init(gates: [1: gate]))
        let (model, _) = GifTestSupport.model(client, accepted: true)
        await model.start()
        let more = Task { await model.loadMore() }
        await gate.untilArrived()

        model.query = "hello"
        await model.submitSearch()
        await gate.open()
        await more.value

        #expect(model.items.count == 3)
        #expect(model.items.first?.id == GifTestSupport.firstSearchID)
        #expect(!model.isLoadingMore)
        #expect(!model.moreFailed)
    }
}
