import Foundation
import HFRModels
import HFRNetwork
import HFRParsing

/// Searches one topic for words or an author (HFR-PROTOCOL S3; audit NET-11): LOT-046.
///
/// One POST of the topic page's search form to `transsearch.php` in the account session, with the session's token and
/// redirects not followed (`ObjCTopicSearchWorker.m:33`): a match answers 302 with the topic page holding it in
/// `Location` (`R52a`), no match answers a `.hop` "Désolé aucune réponse n'a été trouvée" (`R52b`). Legacy read any
/// answer without `Location` as "no result" (`:46-51`); here only HFR's sentence is, so a refused token or an expired
/// session is reported instead of hidden. The `Location` is returned only when it is a topic page of the forum for the
/// searched topic, since the reader then requests it with the session (LESSONS 37, 43). Nothing is retried.
public struct TopicSearchFlow: Sendable {
    /// HFR's sentence for a search without match (`R52b`).
    static let noMatchSentence = "aucune réponse n'a été trouvée"

    /// Creates the flow.
    public init() {}

    /// Searches `query` with the token `session` recorded from the forum's pages.
    /// - Throws: `missingToken` and `network(.invalidRequest)` (no word nor author) before sending, then `network`,
    ///   `notLoggedIn`, `rejected`, `invalidLocation`, `unrecognizedAnswer`.
    public func search(_ query: TopicSearchQuery, in session: HFRSession) async throws(TopicSearchError) -> TopicSearchResult {
        try await search(query, through: session)
    }

    /// Same, through any session (tests: a scripted one).
    func search(_ query: TopicSearchQuery, through session: any PostingSession) async throws(TopicSearchError)
        -> TopicSearchResult {
        guard let token = await session.hashCheck else { throw .missingToken }
        let request: HTTPRequest
        do {
            request = try HFREndpoint.topicSearch(query, hashCheck: token)
        } catch let error as NetworkError {
            throw .network(error)
        } catch {
            throw .network(.invalidRequest(reason: "search request could not be built"))
        }
        guard !Task.isCancelled else { throw .network(.cancelled) }
        let response: HTTPResponse
        do {
            response = try await session.send(request)
        } catch {
            throw .network(error)
        }
        return try Self.result(of: response, searching: query.topic)
    }

    /// Reads HFR's answer: a redirect to a page of `topic` is the match, HFR's sentence is "no match", anything else is
    /// reported through LOT-037's classifier.
    static func result(of response: HTTPResponse, searching topic: TopicID) throws(TopicSearchError) -> TopicSearchResult {
        if response.isRedirect {
            guard let location = response.redirectLocation else { throw .unrecognizedAnswer(message: nil) }
            guard isPage(location, of: topic) else { throw .invalidLocation(location) }
            return .match(location)
        }
        let answer = try? HopResponseParser.classify(html: response.decodedText().text, context: .write, requestURL: response.url)
        if let message = answer?.message, message.contains(noMatchSentence) { return .noMatch }
        switch answer?.kind {
        case .loggedOut: throw .notLoggedIn(message: answer?.message)
        case .rejected: throw .rejected(message: answer?.message)
        default: throw .unrecognizedAnswer(message: answer?.message)
        }
    }

    /// Whether `url` is a `forum2.php` page of the forum for `topic` (category and number).
    static func isPage(_ url: URL, of topic: TopicID) -> Bool {
        PostingFlow.isForumPage(url) && url.path() == "/forum2.php" && HFRURL.topicID(in: url.absoluteString) == topic
    }
}
