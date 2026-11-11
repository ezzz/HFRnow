import Foundation
import HFRModels
import HFRNetwork
import HFRParsing

/// One of the account's flag buckets of the REST API (redface2 E1, LOT-057), and the `owntopic` list of the favourites page
/// that holds the same topics.
public enum RESTFlagBucket: String, Sendable, CaseIterable {
    /// `topics/participated/` (`R335a`): the topics the member took part in, flags and favourites (`owntopic=1`).
    case participated
    /// `topics/read/` (`R335b`): the topics the member has read, "Vos sujets" (`owntopic=2`, `R603e`).
    case read
    /// `topics/favorites/` (`R335c`): the favourites (`owntopic=3`).
    case favorites

    /// The favourites page filter of the same bucket. `flag_owntopic` (`R335a`-`R335c`) numbers the flags as `owntopic`
    /// does, 1 a flag and 3 a favourite; redface2 C12 maps the three buckets the same way, `read` to 2.
    public var filter: TopicListFilter {
        switch self {
        case .participated: .flagged
        case .read: .read
        case .favorites: .favorites
        }
    }
}

/// Reads the account's flag buckets from the JSON REST API, with the favourites page as fallback (LOT-057).
///
/// The REST answer is the whole bucket in one GET (`R335a`-`R335c`; HFR serves no page 2, `R335d`), grouped by category: it
/// becomes the `FavoritesPage` the favourites page gives (`FavoritesParser`, LOT-024). When the REST exchange or its JSON
/// fails, `forum1f.php?owntopic=<1|2|3>` is read instead, and the result says so; a cancelled task, an offline device or a
/// timeout end the call instead, as in `RESTBrowsingClient`.
///
/// Like `FlaggedTopicsPoll`, every request runs in an ephemeral probe `HFRSession` seeded with a snapshot of the account's
/// cookies, and nothing is written back: the account session is only read. No request follows a redirect, so the cookies
/// never reach a topic page, the only page known to move a flag (E25). HFR's stale-session page on the fallback throws
/// `.sessionExpired`, under `FlaggedTopicsPoll`'s rule.
public struct RESTFlagBucketClient: Sendable {
    private let account: HFRSession
    private let makeProbe: (@Sendable ([StoredCookie]) -> any HTTPTransport)?

    /// Creates a client that reads with the cookies of `session`, without ever changing it.
    public init(session: HFRSession) {
        self.account = session
        self.makeProbe = nil
    }

    /// Creates a client with another probe factory (tests).
    init(session: HFRSession, makeProbe: @escaping @Sendable ([StoredCookie]) -> any HTTPTransport) {
        self.account = session
        self.makeProbe = makeProbe
    }

    /// The transport the client sends through: the test factory's, else a fresh session seeded with `cookies` that keeps
    /// the account session's host policy (#365).
    func probe(cookies: [StoredCookie]) -> any HTTPTransport {
        makeProbe?(cookies) ?? account.probe(cookies: cookies, now: Date())
    }

    /// The topics of `bucket`, grouped by category (`R335a`-`R335c`), or the favourites page of the same filter when the
    /// REST answer fails.
    ///
    /// A REST row carries no flag link: it opens at its last page, and its read state is unknown (see the spec). A
    /// fallback page may hold a `notice` instead of sections (`R12`, logged out): as with `FavoritesParser`, the caller
    /// decides from its session.
    /// - Throws: `network` or `page` when the fallback fails too, `network` alone when no fallback is tried,
    ///   `sessionExpired` when the fallback is HFR's stale-session page to the account's current cookies (`R70b`).
    public func topics(in bucket: RESTFlagBucket) async throws(RESTBrowsingError) -> RESTBrowsingResult<FavoritesPage> {
        let seed = await account.refreshSeed(now: Date())
        let probe = probe(cookies: seed.cookies)
        let reason: RESTFallbackReason
        do throws(RESTFailure) {
            let data = try await json(RESTHref.Target(uri: RESTHref.bucketURI(bucket)), on: probe)
            let page = try RESTFailure.reading { () throws(ParsingError) in try RESTDocument.bucket(from: data, bucket: bucket) }
            return RESTBrowsingResult(value: page, source: .rest)
        } catch {
            reason = try Self.fallbackReason(for: error)
        }
        return RESTBrowsingResult(value: try await favoritesPage(bucket, seed: seed, on: probe), source: .html(reason))
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

    /// Sends the REST GET; a redirect is a failure, since HFR answers in place (`R335a`-`R335e`).
    private func json(_ target: RESTHref.Target, on probe: any HTTPTransport) async throws(RESTFailure) -> Data {
        guard !Task.isCancelled else { throw .network(.cancelled) }
        let response: HTTPResponse
        do throws(NetworkError) {
            response = try await probe.send(RESTHref.request(for: target))
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

    /// The favourites page of `bucket`, served in place (`R10`, `R603e`), read with `FavoritesParser`.
    private func favoritesPage(
        _ bucket: RESTFlagBucket, seed: RefreshSeed, on probe: any HTTPTransport
    ) async throws(RESTBrowsingError) -> FavoritesPage {
        let page: RawPage
        let requestedURL: URL
        do {
            var request = try HFREndpoint.favorites(filter: bucket.filter)
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
            // A session that changed meanwhile gets no verdict from an answer to its old cookies: the page is read as is.
            if case .expired(let reason) = health { throw .sessionExpired(reason) }
        }
        guard (200..<300).contains(page.statusCode), page.finalURL == requestedURL else {
            throw .page(.malformed("the favourites page was not served in place (status \(page.statusCode))"))
        }
        do {
            return try FavoritesParser.parse(page.text)
        } catch {
            throw .page(error)
        }
    }
}
