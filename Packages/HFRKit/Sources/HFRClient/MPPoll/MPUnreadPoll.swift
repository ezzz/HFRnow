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
/// expired.
public struct MPUnreadPoll: Sendable {
    private let account: HFRSession
    private let makeProbe: @Sendable ([StoredCookie]) -> any HTTPTransport

    /// Creates a poll that reads the home page with the cookies of `session`, without ever changing it.
    public init(session: HFRSession) {
        self.init(session: session, makeProbe: { HFRSession(cookies: $0) })
    }

    /// Creates a poll with another probe factory (tests).
    init(session: HFRSession, makeProbe: @escaping @Sendable ([StoredCookie]) -> any HTTPTransport) {
        self.account = session
        self.makeProbe = makeProbe
    }

    /// Fetches the home page and returns the unread private messages count it announces.
    /// - Throws: `MPUnreadPollError.network` when the page could not be fetched, `.page` on maintenance or an unreadable page.
    public func unreadCount() async throws(MPUnreadPollError) -> Int? {
        let page: RawPage
        let probe = makeProbe(await account.cookies())
        do {
            // The 5 s background timeout of the legacy check (`MPBackgroundService.swift:86`), not the page default.
            let request = try HFREndpoint.privateMessageCheck()
            if Task.isCancelled { throw NetworkError.cancelled }
            page = RawPage(response: try await probe.send(request))
        } catch let error as NetworkError {
            throw .network(error)
        } catch {
            throw .network(.invalidRequest(reason: "request could not be built"))
        }
        do {
            return try PrivateMessageBadgeParser.unreadCount(in: page.text)
        } catch {
            throw .page(error)
        }
    }
}
