import Foundation
import HFRModels
import HFRNetwork
import HFRParsing

/// Searches the whole forum (HFR-PROTOCOL S1, S2; audit NET-10): LOT-046.
///
/// One POST of the search form to `search.php`, which answers a waiting page whose refresh names the results (`R50a`),
/// then one GET of that URL (`R50b`, `R50c`). The POST, the only request carrying `hash_check`, never follows a redirect;
/// the results URL is requested only when it is an `https` forum page. Everything goes without cookies, as legacy did
/// (`ObjCForumSearchWorker.m:125-146`). Legacy sent the second request as a POST of the same body (`:211-240`); HFR serves
/// the results to a cookie-less GET (`R50b`), so this flow sends a GET.
///
/// A text holding a word legacy replaced with another query (`:150-156`) is refused before anything is sent (decision
/// Q-7): the flow never searches for something the member did not type. "No result" is an empty page carrying HFR's
/// notice (`R50c`), not an error. Nothing is retried, and a cancelled task sends no further request.
public struct GlobalSearchFlow: Sendable {
    /// The words legacy would not search for, matched on the lower-cased text (`ObjCForumSearchWorker.m:150`).
    public static let bannedWords = ["jailbreak", "cydia", "pengu", "apple jb"]

    /// Where every request goes: a transport that sends and stores no cookie.
    let transport: any HTTPTransport

    /// Creates the flow over its own cookie-less transport.
    public init() {
        self.init(transport: AnonymousTransport())
    }

    /// A flow over `transport` (tests: a scripted one).
    init(transport: any HTTPTransport) {
        self.transport = transport
    }

    /// Searches `query` and returns the first results page.
    ///
    /// `hashCheck` is the account's token when one is logged in, else empty: legacy sent its app-wide value on the same
    /// cookie-less request (`ObjCForumSearchWorker.m:159`). What HFR does with either is not captured (LOT-046 spec).
    /// - Throws: `bannedWord` before any request, `network` (request not built or not sent, HTTP error, cancellation),
    ///   `noResultsPage` when the waiting page names no results on the forum, `page` when the results are not a list.
    public func search(_ query: GlobalSearchQuery, hashCheck: String) async throws(GlobalSearchError) -> GlobalSearchResult {
        let text = query.text.lowercased()
        if let word = Self.bannedWords.first(where: { text.contains($0) }) { throw .bannedWord(word) }
        var post: HTTPRequest
        do {
            post = try HFREndpoint.globalSearch(query, hashCheck: hashCheck)
        } catch let error as NetworkError {
            throw .network(error)
        } catch {
            throw .network(.invalidRequest(reason: "search request could not be built"))
        }
        // A followed 307 or 308 would send the body, token included, wherever it points.
        post.redirectPolicy = .doNotFollow
        let waiting = try await fetch(post)
        return try await results(at: Self.resultsURL(in: waiting))
    }

    /// Fetches another results page, from a pager path of a previous result (`TopicListPage.navigation`).
    ///
    /// Only a `forum1.php?…&recherches=1…` page of the forum is requested. Pages after the first are not captured: the
    /// answer is read like the first page (LOT-046 spec, pending capture).
    /// - Throws: `invalidPage` before any request, then as `search`.
    public func page(atPath path: String) async throws(GlobalSearchError) -> GlobalSearchResult {
        guard
            let url = HFRURL.absolute(path),
            PostingFlow.isForumPage(url),
            url.path() == "/forum1.php",
            HFRURL.queryValue(named: "recherches", in: url.absoluteString) == "1"
        else { throw .invalidPage(path) }
        return try await results(at: url)
    }

    // MARK: - Implementation

    /// The results URL the waiting page refreshes to, when it is an `https` page of the forum.
    private static func resultsURL(in waiting: RawPage) throws(GlobalSearchError) -> URL {
        guard !(300..<400).contains(waiting.statusCode) else { throw .noResultsPage(.invalidValue(field: "search answer redirect")) }
        let url: URL
        do {
            url = try SearchRedirectParser.redirectURL(in: waiting.text)
        } catch {
            throw .noResultsPage(error)
        }
        // The parser checks scheme and host; a port or user info is refused here, before any request.
        guard PostingFlow.isForumPage(url) else { throw .noResultsPage(.invalidValue(field: "search redirect URL")) }
        return url
    }

    /// GETs a results page and reads it as a topic list (LOT-022 reads search results and HFR's no-result message).
    private func results(at url: URL) async throws(GlobalSearchError) -> GlobalSearchResult {
        let page = try await fetch(.get(url, timeout: RequestTimeout.globalSearch))
        // The transport follows redirects: a page served from elsewhere is not HFR's answer.
        guard PostingFlow.isForumPage(page.finalURL) else { throw .page(.malformed("search results served off the forum")) }
        do {
            return GlobalSearchResult(url: page.finalURL, page: try TopicListParser.parse(page.text, pageURL: page.finalURL.absoluteString))
        } catch {
            throw .page(error)
        }
    }

    /// Sends one request; checked first, so a search cancelled after its POST never sends the GET.
    private func fetch(_ request: HTTPRequest) async throws(GlobalSearchError) -> RawPage {
        guard !Task.isCancelled else { throw .network(.cancelled) }
        do {
            return RawPage(response: try await transport.send(request))
        } catch {
            throw .network(error)
        }
    }
}
