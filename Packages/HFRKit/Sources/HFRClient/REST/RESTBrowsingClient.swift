import Foundation
import HFRModels
import HFRNetwork
import HFRParsing

/// Reads the forum's categories and lists from the JSON REST API, with the HTML pages as fallback (redface2 E1,
/// LOT-057).
///
/// Every request goes without cookies: the captured REST answers are anonymous (`R57a`-`R57c`), and what HFR answers to
/// a session is not captured, so no account cookie is sent and none can be written back. One GET of
/// `rest_api.php?uri=…` per call, redirects not followed, never retried, never a `posts` resource (HFR answers it
/// 500). When the REST exchange or its JSON fails, the list is read from its HTML page with the existing parser, and the
/// result says so; a cancelled task, an offline device or a timeout end the call instead, since the HTML page would
/// meet the same network.
public struct RESTBrowsingClient: Sendable {
    /// Where every request goes: a transport that sends and stores no cookie.
    let transport: any HTTPTransport

    /// Creates the client over its own cookie-less transport.
    public init() {
        self.init(transport: AnonymousTransport())
    }

    /// A client over `transport` (tests: a scripted one).
    init(transport: any HTTPTransport) {
        self.transport = transport
    }

    /// The forum categories (`R57a`), or the home page's (`ForumListParser`, LOT-021) when the REST answer fails.
    ///
    /// REST categories carry no sub-forums yet (their resource is not captured, #285); the home page's do.
    /// - Throws: `network` or `page` when the fallback fails too, `network` alone when no fallback is tried.
    public func categories() async throws(RESTBrowsingError) -> RESTBrowsingResult<[ForumCategory]> {
        let reason: RESTFallbackReason
        do throws(RESTFailure) {
            let data = try await json(RESTHref.Target(uri: RESTHref.categoriesURI))
            let categories = try RESTFailure.reading { () throws(ParsingError) in try RESTDocument.categories(from: data) }
            return RESTBrowsingResult(value: categories, source: .rest)
        } catch {
            reason = try Self.fallbackReason(for: error)
        }
        let page = try await html { fetcher async throws(NetworkError) in try await fetcher.home(as: .anonymous) }
        do {
            return RESTBrowsingResult(value: try ForumListParser.parse(page.text).forums, source: .html(reason))
        } catch {
            throw .page(error)
        }
    }

    /// The last topics of forum `category`, page 1 (`R57b`), or its HTML list page 1 (`TopicListParser`, LOT-022) when
    /// the REST answer fails. A REST page holds the sticky topics then 25 others; the HTML page, 50 others.
    /// - Throws: `invalidTarget` for a category below 1, before any request; then as `categories()`.
    public func lastTopics(in category: Int) async throws(RESTBrowsingError) -> RESTBrowsingResult<TopicListPage> {
        guard category >= 1 else { throw .invalidTarget }
        let reason: RESTFallbackReason
        do throws(RESTFailure) {
            let data = try await json(RESTHref.Target(uri: RESTHref.lastTopicsURI(category: category)))
            let page = try RESTFailure.reading { () throws(ParsingError) in try RESTDocument.lastTopics(from: data, category: category) }
            return RESTBrowsingResult(value: page, source: .rest)
        } catch {
            reason = try Self.fallbackReason(for: error)
        }
        let page = try await html { fetcher async throws(NetworkError) in
            try await fetcher.topicList(category: .forum(category), page: 1, as: .anonymous)
        }
        do {
            return RESTBrowsingResult(
                value: try TopicListParser.parse(page.text, pageURL: page.finalURL.absoluteString), source: .html(reason)
            )
        } catch {
            throw .page(error)
        }
    }

    /// One topic of a forum (`R57c`). No HTML page summarises a single topic, so there is no fallback.
    /// - Throws: `invalidTarget` before any request for a private or impossible topic, `network`, or `response` when the
    ///   JSON is not that topic.
    public func topic(_ topic: TopicID) async throws(RESTBrowsingError) -> TopicSummary {
        guard case .forum(let category) = topic.category, category >= 1, topic.topic >= 1 else { throw .invalidTarget }
        do throws(RESTFailure) {
            let data = try await json(RESTHref.Target(uri: RESTHref.topicURI(category: category, topic: topic.topic)))
            return try RESTFailure.reading { () throws(ParsingError) in try RESTDocument.topic(from: data, expected: topic) }
        } catch {
            switch error {
            case .network(let network): throw .network(network)
            case .response(let parsing): throw .response(parsing)
            }
        }
    }

    // MARK: - Implementation

    /// A REST failure, before it is turned into a fallback or an error.
    private enum RESTFailure: Error {
        case network(NetworkError)
        case response(ParsingError)

        static func reading<Value>(_ read: () throws(ParsingError) -> Value) throws(RESTFailure) -> Value {
            do {
                return try read()
            } catch {
                throw .response(error)
            }
        }
    }

    /// Sends the REST GET; a redirect is a failure, since HFR answers in place.
    private func json(_ target: RESTHref.Target) async throws(RESTFailure) -> Data {
        guard !Task.isCancelled else { throw .network(.cancelled) }
        let response: HTTPResponse
        do throws(NetworkError) {
            response = try await transport.send(RESTHref.request(for: target))
        } catch {
            throw .network(error)
        }
        guard !response.isRedirect else { throw .network(.httpStatus(code: response.statusCode, url: response.url)) }
        return response.body
    }

    /// The fallback's reason, or the error that ends the call (cancellation, offline, timeout).
    private static func fallbackReason(for failure: RESTFailure) throws(RESTBrowsingError) -> RESTFallbackReason {
        switch failure {
        case .network(let error):
            switch error {
            case .cancelled, .offline, .timedOut: throw .network(error)
            default: return .network(error)
            }
        case .response(let error):
            return .response(error)
        }
    }

    /// Fetches an HTML page on the same cookie-less transport (LOT-045), checked for cancellation first.
    private func html(
        _ fetch: (PageFetcher) async throws(NetworkError) -> RawPage
    ) async throws(RESTBrowsingError) -> RawPage {
        guard !Task.isCancelled else { throw .network(.cancelled) }
        do {
            return try await fetch(PageFetcher(session: transport, anonymous: transport))
        } catch {
            throw .network(error)
        }
    }
}
