import Foundation
import HFRModels
import HFRNetwork
import HFRParsing

/// What the reader needs from the forum: one topic page, fetched and parsed.
protocol TopicPageSource: Sendable {
    /// The page `target` names, fetched with the account session: the user is reading it, so its flags are marked read
    /// (HFR-PROTOCOL §7 E25). Never call it for prefetch.
    func page(for target: ReaderTarget) async throws(ListLoadError) -> ReaderPage
}

/// Turns a message block's raw content into the sanitized `MessageContent` of ADR 0006 (LOT-034's normalizer).
protocol MessageContentNormalizing: Sendable {
    /// The normalized content of `contentHTML`, links resolved against `pageURL`.
    func normalize(contentHTML: String, pageURL: URL) throws(ParsingError) -> MessageContent
}

/// The live source: `PageFetcher` (LOT-045) with the session, then the page parsers (LOT-030, 033) and the normalizer.
///
/// `nonisolated` async functions of a `Sendable` struct run off the main actor, so parsing a long page never blocks the UI.
struct LiveTopicPageSource: TopicPageSource {
    let fetcher: PageFetcher
    /// The account session, for canonical paths that carry no category (`PageFetcher` needs a `TopicID`).
    let session: any HTTPTransport
    let normalizer: any MessageContentNormalizing

    func page(for target: ReaderTarget) async throws(ListLoadError) -> ReaderPage {
        let raw = try await fetch(target)
        return try Self.parse(raw.text, pageURL: raw.finalURL, normalizer: normalizer)
    }

    private func fetch(_ target: ReaderTarget) async throws(ListLoadError) -> RawPage {
        var pathURL: URL?
        if case .path(let path) = target.source {
            guard let url = ReaderTarget.forumURL(path) else { throw .other }
            pathURL = url
        }
        do throws(NetworkError) {
            switch target.source {
            case .topic(let topic):
                return try await fetcher.topicPage(topic: topic, page: target.page, as: .authenticated).page
            case .path:
                guard let pathURL else { throw .invalidRequest(reason: "not a forum link") }
                if Task.isCancelled { throw .cancelled }
                return RawPage(response: try await session.send(.get(pathURL)))
            }
        } catch {
            throw ListLoadError(error)
        }
    }

    /// Builds the reader page from a topic page's HTML; `pageURL` is the final URL after redirects.
    static func parse(_ html: String, pageURL: URL, normalizer: any MessageContentNormalizing) throws(ListLoadError) -> ReaderPage {
        do throws(ParsingError) {
            let metadata = try TopicPageMetadataParser.parse(html: html, pageURL: pageURL.absoluteString)
            let blocks = try MessageBlockParser.blocks(in: html)
            var messages: [ReaderMessage] = []
            messages.reserveCapacity(blocks.count)
            for block in blocks {
                messages.append(ReaderMessage(
                    numreponse: block.numreponse,
                    author: block.author,
                    isDeleted: block.isDeleted,
                    isContinuation: block.isContinuation,
                    avatarURL: block.avatarURL,
                    dateText: block.dateText,
                    editNote: block.editNote,
                    quotedByCount: block.quotedByCount,
                    content: try normalizer.normalize(contentHTML: block.contentHTML, pageURL: pageURL)
                ))
            }
            return ReaderPage(
                topicID: metadata.topicID,
                title: metadata.title,
                currentPage: max(1, metadata.currentPage),
                maxPage: max(1, metadata.maxPage, metadata.currentPage),
                messages: messages
            )
        } catch {
            throw .unreadable
        }
    }
}
