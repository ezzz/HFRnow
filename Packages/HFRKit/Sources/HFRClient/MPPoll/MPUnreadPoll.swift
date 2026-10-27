import HFRModels
import HFRNetwork
import HFRParsing

/// Reads the unread private messages count with one cheap request; when and how often to poll is the app's business.
///
/// The count comes from the home page (`/`), the page legacy polled (`MPBackgroundService.swift:79-139`): one GET that
/// carries the `cat=prive` row (R02, R03) and none of the flags, so it cannot mark anything read (HFR-PROTOCOL §7, E25
/// concerns topic pages, which this flow never requests). The page is read with the account's session; the cookie-less
/// transport is never used, since a logged-out home page has no entry to read.
///
/// The result is `PrivateMessageBadgeParser`'s: a number, `0` for an entry without a number, `nil` for no entry at all.
/// `nil` means "no information" (logged out, or an unexpected page), never "no unread": it must not be stored as 0 and
/// it is not proof the session expired. The flow never touches the session; confirming a logged-out look is
/// `SessionRefreshFlow` (LOT-044), on the app's decision.
public struct MPUnreadPoll: Sendable {
    private let fetcher: PageFetcher

    /// Creates a poll that reads the home page through the account's session.
    public init(session: any HTTPTransport) {
        self.init(session: session, anonymous: AnonymousTransport())
    }

    /// Creates a poll with another cookie-less transport (tests assert that it stays unused).
    init(session: any HTTPTransport, anonymous: any HTTPTransport) {
        self.fetcher = PageFetcher(session: session, anonymous: anonymous)
    }

    /// Fetches the home page and returns the unread private messages count it announces.
    /// - Throws: `MPUnreadPollError.network` when the page could not be fetched, `.page` on maintenance or an unreadable page.
    public func unreadCount() async throws(MPUnreadPollError) -> Int? {
        let page: RawPage
        do {
            page = try await fetcher.home(as: .authenticated)
        } catch {
            throw .network(error)
        }
        do {
            return try PrivateMessageBadgeParser.unreadCount(in: page.text)
        } catch {
            throw .page(error)
        }
    }
}
