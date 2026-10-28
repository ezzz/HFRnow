import Foundation
import HFRModels
import HFRNetwork
import HFRParsing

/// Checks an account session against HFR and merges the cookies HFR refreshes (LOT-044, audit NET-07).
///
/// Replaces the legacy launch-time `updateAllAccounts` (`MultisManager.m:242-293`), which overwrote an account's stored
/// cookies with only those of the answer, whatever the page said. Here the request runs in a probe jar seeded with the
/// session's cookies; the session changes only when the answer is the account's own profile page, so an ambiguous
/// page never logs an account out. When to refresh (launch, after a flow saw a logged-out notice) is the app's call:
/// flows that meet such a notice (LOT-023 `.notAuthenticated`, LOT-037 `.loggedOut`) re-check it here instead of
/// clearing the session; a `valid` clears the doubt, anything else leaves the session alone.
public struct SessionRefreshFlow: Sendable {
    private let makeProbe: @Sendable ([StoredCookie], Date) -> any SessionJar

    /// A flow whose probes are fresh `HFRSession`s.
    public init() {
        self.init { cookies, now in HFRSession(cookies: cookies, now: now) }
    }

    /// A flow with another probe factory (tests).
    init(makeProbe: @escaping @Sendable ([StoredCookie], Date) -> any SessionJar) {
        self.makeProbe = makeProbe
    }

    /// GETs the profile page 1 with `session`'s cookies and reports what HFR's answer says about the session.
    ///
    /// `valid` merges the cookies HFR set or removed and the page's `hash_check` into `session`; on every other outcome,
    /// and every thrown error, the flow writes nothing (concurrent requests may still change `session`). A session
    /// without a usable `md_user` is `expired` and nothing is sent.
    /// - Throws: the transport's `NetworkError` (4xx/5xx, timeout, offline, cancelled).
    public func refresh(_ session: HFRSession, now: Date = Date()) async throws(NetworkError) -> SessionHealth {
        let seed = await session.refreshSeed(now: now)
        guard let identity = seed.identity else { return .expired(.noIdentityCookie) }
        var request = try Self.profilePageRequest()
        // A redirect (to page 5, to the login page) is not page 1: return it and let the URL check refuse it.
        request.redirectPolicy = .doNotFollow
        let probe = makeProbe(seed.cookies, now)
        let response = try await probe.send(request)
        guard let token = Self.accountToken(in: response, expectedURL: request.url) else {
            return .unconfirmed(.unrecognizedPage)
        }
        // Read after the answer: logged-in pages set `md_user` and `md_passs` again (`R55-p1` meta).
        guard await probe.userKey(now: now) == identity else { return .unconfirmed(.identityNotConfirmed) }
        let update = RefreshUpdate(seed: seed.cookies, after: await probe.cookies(now: now), hashCheck: token)
        return try await session.adoptRefresh(update, seed: seed, now: now)
    }

    // MARK: - Rules

    private static func profilePageRequest() throws(NetworkError) -> HTTPRequest {
        do {
            return try HFREndpoint.editProfile(page: .cookieRefresh)
        } catch let error as NetworkError {
            throw error
        } catch {
            throw .invalidRequest(reason: "profile page request")
        }
    }

    /// The page's `hash_check` when the answer is the profile edit page of a logged-in account, else nil.
    ///
    /// HFR prints the token on its pages only for a logged-in session (empty on `R01`, `W00`, `R40b`); a GET answer
    /// cannot echo one back. A `.hop` notice is refused even with a token: a replayed form can carry the token it was
    /// posted with (`W17c`). The answer must be a 2xx served at exactly `expectedURL`, the profile page 1 of the forum
    /// over HTTPS (port absent or 443, LESSONS 37), not a page reached by a redirect or from another origin.
    static func accountToken(in response: HTTPResponse, expectedURL: URL) -> String? {
        guard
            (200..<300).contains(response.statusCode), response.url == expectedURL, isForumProfilePage(response.url)
        else { return nil }
        let html = response.decodedText().text
        guard
            let hop = try? HopResponseParser.classify(html: html, requestURL: response.url),
            hop.kind == .unrecognized, hop.message == nil,
            let page = try? ProfileEditPageParser.parse(html)
        else { return nil }
        return page.hashCheck
    }

    private static func isForumProfilePage(_ url: URL) -> Bool {
        url.scheme?.lowercased() == "https"
            && url.host?.lowercased() == HFRURL.base.host?.lowercased()
            && (url.port == nil || url.port == 443)
            && url.path == "/user/editprofil.php"
    }
}
