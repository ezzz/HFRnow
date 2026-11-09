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

/// LOT-034's normalizer: the sanitizer of record (ADR 0006); fragment-only links resolve against the page URL.
struct LiveContentNormalizer: MessageContentNormalizing {
    func normalize(contentHTML: String, pageURL: URL) throws(ParsingError) -> MessageContent {
        try MessageContentNormalizer.normalize(contentHTML: contentHTML, relativeTo: pageURL)
    }
}

/// The live source: `PageFetcher` (LOT-045) with the session, then the page parsers (LOT-030, 033) and the normalizer.
///
/// `nonisolated` async functions of a `Sendable` struct run off the main actor, so parsing a long page never blocks the UI.
struct LiveTopicPageSource: TopicPageSource {
    let fetcher: PageFetcher
    /// The account session, for a message link (`PageFetcher` asks for a page, R25 needs page 1 plus the message).
    let session: any HTTPTransport
    let normalizer: any MessageContentNormalizing

    func page(for target: ReaderTarget) async throws(ListLoadError) -> ReaderPage {
        let raw = try await fetch(target)
        return try Self.parse(raw.text, pageURL: raw.finalURL, normalizer: normalizer)
    }

    private func fetch(_ target: ReaderTarget) async throws(ListLoadError) -> RawPage {
        do throws(NetworkError) {
            switch target.source {
            case .topic(let topic):
                if let numreponse = target.numreponse {
                    // `forum2.php?…&page=1&numreponse=M`: HFR redirects to the page holding M (R25); the final URL gives it.
                    if Task.isCancelled { throw .cancelled }
                    return RawPage(response: try await session.send(try Self.messageRequest(topic: topic, numreponse: numreponse)))
                }
                return try await fetcher.topicPage(topic: topic, page: target.page, as: .authenticated).page
            }
        } catch {
            throw ListLoadError(error)
        }
    }

    /// LOT-095's request for a message whose page is unknown: page 1 plus `numreponse`, exactly the shape of `R25`.
    static func messageRequest(topic: TopicID, numreponse: Int) throws(NetworkError) -> HTTPRequest {
        do {
            return try HFREndpoint.topicPage(topic: topic, page: 1, numreponse: numreponse)
        } catch {
            throw .invalidRequest(reason: "message link")
        }
    }

    /// Builds the reader page from a topic page's HTML; `pageURL` is the final URL after redirects.
    static func parse(_ html: String, pageURL: URL, normalizer: any MessageContentNormalizing) throws(ListLoadError) -> ReaderPage {
        var page: ReaderPage
        do throws(ParsingError) {
            let metadata = try TopicPageMetadataParser.parse(html: html, pageURL: pageURL.absoluteString)
            let blocks = try MessageBlockParser.blocks(in: html)
            // One action set per block, in the blocks' order (LOT-031); a count that differs would mismatch messages and
            // links, so no message then offers an action.
            let actionSets = try MessageActionsParser.actions(in: html)
            let hasActions = actionSets.count == blocks.count
            var messages: [ReaderMessage] = []
            messages.reserveCapacity(blocks.count)
            for (index, block) in blocks.enumerated() {
                let content = try normalizer.normalize(contentHTML: block.contentHTML, pageURL: pageURL)
                messages.append(ReaderMessage(
                    numreponse: block.numreponse,
                    author: block.author,
                    isDeleted: block.isDeleted,
                    isContinuation: block.isContinuation,
                    avatarURL: block.avatarURL,
                    dateText: block.dateText,
                    editNote: block.editNote,
                    quotedByCount: block.quotedByCount,
                    content: content,
                    quotes: ReaderMessage.quotes(of: content),
                    actions: hasActions ? actionSets[index] : MessageActions()
                ))
            }
            page = ReaderPage(
                topicID: metadata.topicID,
                title: metadata.title,
                currentPage: max(1, metadata.currentPage),
                maxPage: max(1, metadata.maxPage, metadata.currentPage),
                messages: messages,
                answerURL: metadata.answerFormURL,
                pageURL: ReaderTarget.forumURL(pageURL.absoluteString),
                poll: metadata.hasPoll ? try? PollParser.poll(in: html) : nil,
                markUnreadURL: metadata.markUnreadURL
            )
        } catch {
            throw .unreadable
        }
        if page.messages.isEmpty { page.notice = try notice(in: html, pageURL: pageURL) }
        return page
    }

    /// A page without any message may be one of HFR's message pages: the maintenance page and the `.hop` notices are
    /// read by the list parser's classification (LOT-022), so the reader shows HFR's text instead of "no message".
    private static func notice(in html: String, pageURL: URL) throws(ListLoadError) -> String? {
        do throws(ListPageFailure) {
            return try TopicListParser.parse(html, pageURL: pageURL.absoluteString).notice
        } catch .malformed {
            return nil
        } catch {
            throw ListLoadError(error)
        }
    }
}
