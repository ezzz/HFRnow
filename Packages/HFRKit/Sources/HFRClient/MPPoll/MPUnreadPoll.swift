import Foundation
import HFRModels
import HFRNetwork
import HFRParsing

/// Reads the unread private messages count with one cheap request; when and how often to poll is the app's business.
///
/// The count comes from the home page (`/`), the page legacy polled (`MPBackgroundService.swift:70-107`): one GET that
/// carries the `cat=prive` row (R02, R03) and none of the flags, so it cannot mark anything read (HFR-PROTOCOL §7, E25
/// concerns topic pages, which this flow never requests).
///
/// A logged-in `GET /` answers with `Set-Cookie` for `md_user` and `md_passs` (R02, R03 metas). The request therefore runs in
/// an ephemeral probe `HFRSession` seeded with a snapshot of the account session's cookies, and nothing is written back: a
/// poll that started before a login (LOT-043) or a refresh (LOT-044) cannot overwrite the cookies they installed. Refreshing
/// cookies is `SessionRefreshFlow`'s job. The account session is only read.
///
/// The result is `PrivateMessageBadgeParser`'s: a number, `0` for an entry without a number, `nil` for no entry at all.
/// `nil` means "no information" (logged out, or a page that is not the expected one, including a logged-in home whose markup
/// changed, which the app cannot tell apart), never "no unread": it must not be stored as 0 and it is not proof the session
/// expired. The one answer that is such proof, HFR's stale-session page (`R70a`, #383), throws `.sessionExpired` instead,
/// with `SessionRefreshFlow`'s reason and under its rule: only while the account still holds the cookies the poll sent.
public struct MPUnreadPoll: Sendable {
    private let account: HFRSession
    private let makeProbe: (@Sendable ([StoredCookie]) -> any HTTPTransport)?

    /// Creates a poll that reads the home page with the cookies of `session`, without ever changing it.
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
    /// the account session's host policy (#365, as `SessionRefreshFlow`).
    func probe(cookies: [StoredCookie]) -> any HTTPTransport {
        makeProbe?(cookies) ?? account.probe(cookies: cookies, now: Date())
    }

    /// Fetches the home page and returns the unread private messages count it announces.
    /// - Throws: `MPUnreadPollError.network` when the page could not be fetched, `.page` on maintenance or an unreadable page,
    ///   `.sessionExpired` when HFR answered with its stale-session page (`R70a`) to the account's current cookies.
    public func unreadCount() async throws(MPUnreadPollError) -> Int? {
        let page: RawPage
        let requestedURL: URL
        let seed = await account.refreshSeed(now: Date())
        let probe = probe(cookies: seed.cookies)
        do {
            // The 5 s background timeout of the legacy check (`MPBackgroundService.swift:86`), not the page default.
            let request = try HFREndpoint.privateMessageCheck()
            requestedURL = request.url
            if Task.isCancelled { throw NetworkError.cancelled }
            page = RawPage(response: try await probe.send(request))
        } catch let error as NetworkError {
            throw .network(error)
        } catch {
            throw .network(.invalidRequest(reason: "request could not be built"))
        }
        if StaleSessionAnswer.matches(page, requestedURL: requestedURL) {
            // HFR's own word that it refuses these cookies (`R70a`, the same bytes as `R70c`): the account session's
            // verdict, not a count. A session that changed meanwhile gets no verdict from an answer to its old cookies.
            let health: SessionHealth
            do {
                health = try await account.confirmStaleSession(seed: seed, now: Date())
            } catch {
                throw .network(error)
            }
            if case .expired(let reason) = health { throw .sessionExpired(reason) }
            return nil
        }
        do {
            return try PrivateMessageBadgeParser.unreadCount(in: page.text)
        } catch {
            throw .page(error)
        }
    }
}
