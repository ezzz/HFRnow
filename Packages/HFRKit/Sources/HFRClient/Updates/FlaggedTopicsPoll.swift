import Foundation
import HFRModels
import HFRNetwork
import HFRParsing

/// Why a flagged topics poll gave no answer.
public enum FlaggedTopicsPollError: Error, Sendable, Equatable {
    /// The flags page could not be fetched (offline, timeout, HTTP 4xx/5xx, cancellation).
    case network(NetworkError)
    /// HFR answered, but the page is in maintenance, unreadable, or not served in place (`ListPageFailure`).
    case page(ListPageFailure)
    /// HFR refused the account's cookies (its stale-session page, `R70b`), as `SessionRefreshFlow` reports it (#383).
    case sessionExpired(SessionExpiry)
}

/// Reads the account's flagged topics (flags or favourites, see `TopicSummary.flag`) with one request to the
/// flags page (`GET /forum1f.php?owntopic=1`), the page legacy loaded
/// for the same list (`ObjCFavoritesLoaderWorker.m:46-48`). When and how often to poll is the app's business.
///
/// **It cannot mark a flag read.** HFR moves a flag on an authenticated *topic* page (HFR-PROTOCOL §7, E25, `R21`), which
/// this poll never requests: the request is built by `HFREndpoint.favorites(filter: .flagged)` and sent with
/// `redirectPolicy = .doNotFollow`, so even a redirect cannot lead the account's cookies to a topic page. The flags page
/// itself is not known to move flags, and the committed captures (`R10`, `R73a`) cannot show it: the fixture kit re-aliases
/// ids and pages by row position. What holds is structural: no topic page is requested and redirects are refused (E25).
/// Pending capture: two raw flags pages around a poll, compared without publishing values (HFR-PROTOCOL §6c, LOT-092).
///
/// Like `MPUnreadPoll`, the request runs in an ephemeral probe `HFRSession` seeded with a snapshot of the account's
/// cookies (a logged-in answer sets `md_user` and `md_passs` again, `R10` meta) and nothing is written back, so a poll that
/// started before a login (LOT-043) or a refresh (LOT-044) cannot overwrite what they installed.
///
/// The result is `nil` for "no information": a `.hop` page that is not the stale-session page (the logged-out `R12`), which a
/// caller must never store as "no flagged topic". A list body without any row is a confirmed empty list (`R123g`): `[]`.
/// HFR's stale-session page (`R70b`) throws `.sessionExpired`, under `MPUnreadPoll`'s rule: only while the account still
/// holds the cookies the poll sent.
public struct FlaggedTopicsPoll: Sendable {
    private let account: HFRSession
    private let makeProbe: (@Sendable ([StoredCookie]) -> any HTTPTransport)?

    /// Creates a poll that reads the flags page with the cookies of `session`, without ever changing it.
    public init(session: HFRSession) {
        self.account = session
        self.makeProbe = nil
    }

    /// Creates a poll with another probe factory (tests).
    init(session: HFRSession, makeProbe: @escaping @Sendable ([StoredCookie]) -> any HTTPTransport) {
        self.account = session
        self.makeProbe = makeProbe
    }

    /// The transport the poll sends through: the test factory's, else a fresh session seeded with `cookies` that keeps
    /// the account session's host policy (#365).
    func probe(cookies: [StoredCookie]) -> any HTTPTransport {
        makeProbe?(cookies) ?? account.probe(cookies: cookies, now: Date())
    }

    /// Fetches the flags page and returns its topics, the most recent last post first.
    /// - Returns: the flagged topics (empty: a confirmed empty list), or nil when the answer gives no information.
    /// - Throws: `.network` when the page could not be fetched, `.page` on maintenance, an unreadable page or an answer
    ///   that is not the page served in place, `.sessionExpired` on the stale-session page (`R70b`).
    public func flaggedTopics() async throws(FlaggedTopicsPollError) -> [TopicSummary]? {
        let page: RawPage
        let requestedURL: URL
        let seed = await account.refreshSeed(now: Date())
        let probe = probe(cookies: seed.cookies)
        do {
            var request = try HFREndpoint.favorites(filter: .flagged)
            // A redirect is not the list: refuse it below instead of sending the cookies on to wherever it leads.
            request.redirectPolicy = .doNotFollow
            requestedURL = request.url
            if Task.isCancelled { throw NetworkError.cancelled }
            page = RawPage(response: try await probe.send(request))
        } catch let error as NetworkError {
            throw .network(error)
        } catch {
            throw .network(.invalidRequest(reason: "request could not be built"))
        }
        if StaleSessionAnswer.matches(page, requestedURL: requestedURL) {
            let health: SessionHealth
            do {
                health = try await account.confirmStaleSession(seed: seed, now: Date())
            } catch {
                throw .network(error)
            }
            if case .expired(let reason) = health { throw .sessionExpired(reason) }
            return nil
        }
        guard (200..<300).contains(page.statusCode), page.finalURL == requestedURL else {
            throw .page(.malformed("the flags page was not served in place (status \(page.statusCode))"))
        }
        do {
            let parsed = try FavoritesParser.parse(page.text)
            // A `.hop` notice instead of the list: the logged-out page (`R12`) or an unknown one, never "nothing flagged".
            if parsed.notice != nil { return nil }
            return parsed.topicsByLastPost
        } catch {
            throw .page(error)
        }
    }
}
