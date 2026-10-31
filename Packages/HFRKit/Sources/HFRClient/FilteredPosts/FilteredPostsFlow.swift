import Foundation
import HFRModels
import HFRNetwork
import HFRParsing

/// Reads a topic page after page and keeps the messages that matter (LOT-093, legacy "Filtrer les posts").
///
/// Pages are fetched **without cookies**, as legacy did (`FilterPostsQuotes.m:261-267`: no cookie persistence, empty
/// request cookies): no account session is reachable from this flow, so filtering never moves the account's read flag
/// (HFR-PROTOCOL §7 E25), and the account's own pages are read as a visitor sees them.
public struct FilteredPostsFlow: Sendable {
    /// A batch stops after the page that brings it to this many messages (legacy: `arrData.count >= 40`, `:298`).
    public static let batchSize = 40

    private let fetcher: PageFetcher

    /// Creates the flow over its own cookie-less transport.
    public init() {
        self.init(transport: AnonymousTransport())
    }

    /// A flow over `transport` (tests: a scripted one); every page goes through it.
    init(transport: any HTTPTransport) {
        fetcher = PageFetcher(session: transport, anonymous: transport)
    }

    /// Filters `topic` from `startPage` until a batch is full or the topic's last page is read.
    ///
    /// `after` skips, on the first page only, the messages up to that one (the last message read, legacy's `#t<id>` of
    /// the favourite link, `:237-243`). `progress` is called after each page. The continuation block that opens pages 2
    /// and later (a copy of the previous page's last message) is never kept. Cancellation is checked before each page.
    /// - Throws: `invalidTopic` before any request, then `network`, `unexpectedPage` or `page` for the page that failed.
    public func posts(
        in topic: TopicID,
        from startPage: Int,
        after message: Int? = nil,
        criteria: FilteredPostsCriteria,
        progress: @Sendable (FilteredPostsProgress) async -> Void = { _ in }
    ) async throws(FilteredPostsError) -> FilteredPostsBatch {
        guard case .forum(let category) = topic.category, category > 0, topic.topic > 0, startPage >= 1 else {
            throw .invalidTopic
        }
        var posts: [FilteredPost] = []
        var page = startPage
        while true {
            let blocks: [MessageBlock]
            let maxPage: Int
            switch try await read(page, of: topic) {
            case .pastEnd(let lastPage):
                // HFR served its last page instead (`R24`): the topic ends before `page`.
                return FilteredPostsBatch(
                    posts: posts, startPage: startPage, endPage: max(page - 1, startPage), maxPage: lastPage, isFinished: true
                )
            case .page(let read, let last):
                (blocks, maxPage) = (read, last)
            }
            posts += try Self.kept(blocks, page: page, after: page == startPage ? message : nil, criteria: criteria)
            await progress(FilteredPostsProgress(page: page, maxPage: maxPage, resultCount: posts.count))
            if page >= maxPage || posts.count >= Self.batchSize {
                return FilteredPostsBatch(
                    posts: posts, startPage: startPage, endPage: page, maxPage: maxPage, isFinished: page >= maxPage
                )
            }
            page += 1
        }
    }

    /// The messages of `page` that `criteria` keeps, the continuation block and the messages up to `after` left out.
    private static func kept(
        _ blocks: [MessageBlock], page: Int, after message: Int?, criteria: FilteredPostsCriteria
    ) throws(FilteredPostsError) -> [FilteredPost] {
        var kept: [FilteredPost] = []
        for block in blocks where !block.isContinuation && block.numreponse > (message ?? 0) {
            let quotes: [MessageQuote]
            do {
                quotes = try MessageQuoteAnalyzer.quotes(inContentHTML: block.contentHTML)
            } catch {
                throw .page(error)
            }
            if criteria.keeps(block, quotes: quotes) { kept.append(FilteredPost(page: page, block: block, quotes: quotes)) }
        }
        return kept
    }

    /// What one fetch gave: the page's blocks and the topic's last page, or HFR's last page served instead of `page`.
    private enum PageRead {
        case page(blocks: [MessageBlock], maxPage: Int)
        case pastEnd(lastPage: Int)
    }

    private func read(_ page: Int, of topic: TopicID) async throws(FilteredPostsError) -> PageRead {
        let fetched: FetchedTopicPage
        // A cancelled task sends nothing: `PageFetcher` checks it before each request (`NetworkError.cancelled`).
        do {
            fetched = try await fetcher.topicPage(topic: topic, page: page, as: .anonymous)
        } catch {
            throw .network(error)
        }
        guard let location = fetched.location, location.topic == topic.topic else { throw .unexpectedPage }
        guard location.page == page else { return .pastEnd(lastPage: location.page) }
        let html = fetched.page.text
        let blocks: [MessageBlock]
        let metadata: TopicPageMetadata
        do {
            blocks = try MessageBlockParser.blocks(in: html)
            metadata = try TopicPageMetadataParser.parse(html: html, pageURL: fetched.page.finalURL.absoluteString)
        } catch {
            throw .page(error)
        }
        // Every topic page holds a message: page 1 its first post, later pages the continuation block at least.
        guard !blocks.isEmpty else { throw .unexpectedPage }
        return .page(blocks: blocks, maxPage: max(metadata.maxPage, page))
    }
}
