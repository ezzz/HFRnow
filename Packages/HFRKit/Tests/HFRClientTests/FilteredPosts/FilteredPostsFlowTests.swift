import Foundation
import HFRModels
import HFRNetwork
import HFRParsing
import Testing
@testable import HFRClient

/// The page walk: which pages are requested, how a batch ends, what is reported, on the captured anonymous pages of
/// topic 28563 (`R20` page 1, `R22a` page 1100, `R22b` its last page 2201, `R24` page 2202 answered with page 2201).
@Suite("Post filter: page walk")
struct FilteredPostsFlowTests {
    private static let pizza = TopicID(category: .forum(13), topic: 28563)
    /// Keeps nothing: no account, no allowlist, an unreachable count.
    private static let none = FilteredPostsCriteria(minimumQuoteCount: 1_000)

    /// The capture `id` as served, at its final URL.
    private static func served(_ id: String) throws -> Result<HTTPResponse, NetworkError> {
        let meta = try Capture.meta(id)
        let names = try FileManager.default.contentsOfDirectory(atPath: Capture.directory.path)
        guard let file = names.first(where: { $0.hasPrefix(id + "-") && $0.hasSuffix(".html") }) else {
            throw Capture.Missing(name: id)
        }
        return .success(try Capture.response(String(file.dropLast(5)), url: PostingCapture.url(meta.finalURL ?? meta.url)))
    }

    /// Progress reports, in order.
    private actor Reports {
        var values: [FilteredPostsProgress] = []
        func record(_ value: FilteredPostsProgress) { values.append(value) }
    }

    /// What one run produced.
    private struct Outcome {
        let result: Result<FilteredPostsBatch, FilteredPostsError>
        let requests: [HTTPRequest]
        let progress: [FilteredPostsProgress]

        var batch: FilteredPostsBatch? { try? result.get() }
        var error: FilteredPostsError? {
            if case .failure(let error) = result { return error }
            return nil
        }
        /// The page number of each request, read from the `forum2.php` query.
        var pages: [String] {
            requests.map { HFRURL.queryValue(named: "page", in: $0.url.absoluteString) ?? "?" }
        }
    }

    private static func run(
        _ replies: [Result<HTTPResponse, NetworkError>], topic: TopicID = pizza, from page: Int, after message: Int? = nil,
        criteria: FilteredPostsCriteria = none
    ) async -> Outcome {
        let transport = MockTransport(replies: replies)
        let reports = Reports()
        let result: Result<FilteredPostsBatch, FilteredPostsError>
        do {
            result = .success(try await FilteredPostsFlow(transport: transport).posts(
                in: topic, from: page, after: message, criteria: criteria
            ) { await reports.record($0) })
        } catch {
            result = .failure(error)
        }
        return Outcome(result: result, requests: await transport.requests, progress: await reports.values)
    }

    /// Every author of the capture: an allowlist that keeps every message.
    private static func everyone(_ id: String) throws -> FilteredPostsCriteria {
        guard let file = Self.pageFiles[id] else { throw Capture.Missing(name: id) }
        let page = try Capture.page(file)
        return FilteredPostsCriteria(allowlist: try MessageBlockParser.blocks(in: page).map(\.author))
    }

    private static let pageFiles = [
        "R20": "R20-topic-p1-anon", "R22a": "R22a-topic-middle-page-anon", "R22b": "R22b-topic-last-page-anon"
    ]

    // MARK: - Pages

    @Test("The last page ends the batch as finished: one anonymous GET, one progress report, no resume page")
    func lastPage() async throws {
        let outcome = await Self.run([try Self.served("R22b")], from: 2201, criteria: try Self.everyone("R22b"))
        let batch = try #require(outcome.batch)
        #expect(outcome.pages == ["2201"])
        #expect(outcome.requests.allSatisfy { $0.method == .get && $0.headers["Cookie"] == nil })
        #expect((batch.startPage, batch.endPage, batch.maxPage, batch.isFinished) == (2201, 2201, 2201, true))
        #expect(batch.resumePage == nil)
        // The continuation block opening the page is never kept, even when its author is allowlisted.
        let blocks = try MessageBlockParser.blocks(in: try Capture.page("R22b-topic-last-page-anon"))
        #expect(blocks.first?.isContinuation == true)
        #expect(batch.posts.map(\.block.numreponse) == blocks.dropFirst().map(\.numreponse))
        #expect(batch.posts.allSatisfy { $0.page == 2201 })
        #expect(outcome.progress == [FilteredPostsProgress(page: 2201, maxPage: 2201, resultCount: blocks.count - 1)])
    }

    @Test("A page that brings the batch to 40 messages ends it; the next batch starts on the next page")
    func fullBatch() async throws {
        let outcome = await Self.run([try Self.served("R20")], from: 1, criteria: try Self.everyone("R20"))
        let batch = try #require(outcome.batch)
        #expect(outcome.pages == ["1"])
        // Page 1 has no continuation block: its first post is a message like the others (legacy dropped it).
        #expect(batch.posts.count == 40)
        #expect(batch.posts.first?.block.numreponse == 2666649)
        #expect((batch.endPage, batch.maxPage, batch.isFinished, batch.resumePage) == (1, 2201, false, 2))
    }

    @Test("A short batch goes on to the next page; a failure there ends the run with the error, after one request")
    func nextPageFailure() async throws {
        let outcome = await Self.run([try Self.served("R20"), .failure(.offline)], from: 1)
        #expect(outcome.error == .network(.offline))
        #expect(outcome.pages == ["1", "2"])
        #expect(outcome.progress.map(\.page) == [1])
    }

    @Test("Cancelled after a page, the run requests nothing more")
    func cancellationBetweenPages() async throws {
        let transport = MockTransport(replies: [try Self.served("R20"), try Self.served("R22a")])
        let task = Task {
            try await FilteredPostsFlow(transport: transport).posts(in: Self.pizza, from: 1, criteria: Self.none) { _ in
                withUnsafeCurrentTask { $0?.cancel() }
            }
        }
        let result = await task.result
        #expect(throws: FilteredPostsError.network(.cancelled)) { try result.get() }
        #expect(await transport.requests.count == 1)
    }

    @Test("A page past the end, answered with the last page (R24), ends the batch without reading it again")
    func pastTheEnd() async throws {
        let outcome = await Self.run([try Self.served("R24")], from: 2202, criteria: try Self.everyone("R22b"))
        let batch = try #require(outcome.batch)
        #expect(batch.posts.isEmpty)
        #expect((batch.startPage, batch.endPage, batch.maxPage, batch.isFinished) == (2202, 2202, 2201, true))
        #expect(outcome.progress.isEmpty)
    }

    @Test("`after` skips the first page's messages up to the last one read")
    func afterLastRead() async throws {
        let blocks = try MessageBlockParser.blocks(in: try Capture.page("R22a-topic-middle-page-anon"))
        let lastRead = blocks[10].numreponse
        let outcome = await Self.run(
            [try Self.served("R22a"), .failure(.offline)], from: 1100, after: lastRead, criteria: try Self.everyone("R22a")
        )
        #expect(outcome.error == .network(.offline))
        #expect(outcome.progress.first?.resultCount == blocks.count - 11)
    }

    // MARK: - Refusals

    @Test(
        "Only a forum topic, from page 1, is filtered: nothing is requested otherwise",
        arguments: [
            (TopicID(category: .privateMessages, topic: 3207033), 1), (TopicID(category: .forum(0), topic: 1), 1),
            (TopicID(category: .forum(13), topic: 0), 1), (TopicID(category: .forum(13), topic: 28563), 0)
        ]
    )
    func invalidTopic(topic: TopicID, page: Int) async {
        let outcome = await Self.run([], topic: topic, from: page)
        #expect(outcome.error == .invalidTopic)
        #expect(outcome.requests.isEmpty)
    }

    @Test("Another topic's page (R23 for topic 28563) is not this topic's")
    func otherTopic() async throws {
        let outcome = await Self.run([try Self.served("R23")], from: 1)
        #expect(outcome.error == .unexpectedPage)
    }

    @Test("A page without message (the list page R04 at a topic URL, a derived probe) is not a topic page")
    func pageWithoutMessage() async throws {
        let page = HTTPResponse(
            statusCode: 200, headers: ["Content-Type": "text/html; charset=utf-8"],
            url: PostingCapture.url("https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm"),
            body: Data(try Capture.page("R04-list-cat13-p1-anon").utf8)
        )
        let outcome = await Self.run([.success(page)], from: 1)
        #expect(outcome.error == .unexpectedPage)
    }

    @Test("An HTTP error is reported as such")
    func httpError() async {
        let url = PostingCapture.url("https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=28563&page=1")
        let outcome = await Self.run([.failure(.httpStatus(code: 500, url: url))], from: 1)
        #expect(outcome.error == .network(.httpStatus(code: 500, url: url)))
    }

    @Test("The public flow reads through its own cookie-less transport")
    func publicFlowIsCookieless() throws {
        let fetcher = try #require(Mirror(reflecting: FilteredPostsFlow()).children.first?.value)
        let transports = Mirror(reflecting: fetcher).children.map(\.value)
        #expect(transports.count == 2)
        #expect(transports.allSatisfy { $0 is AnonymousTransport })
    }
}
