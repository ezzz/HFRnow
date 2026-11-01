import HFRModels
import HFRNetwork
import HFRParsing

/// Searches HFR's smileys by keyword and reads a smiley's wiki keywords (LOT-053, audit NET-12).
///
/// Two read-only GETs over existing pieces: the search (`HFREndpoint.smileySearch`, `SmileySearchParser`) and the wiki
/// entry (`HFREndpoint.smileyWiki`, `SmileyWikiDetailParser`). The search was captured logged in (`R53a`-`R53c`) and legacy
/// sent it with the shared cookies (`SmileySearchService.swift:25`), so it runs in an ephemeral probe `HFRSession` seeded
/// with the account's cookies, as `MPUnreadPoll` does: whatever HFR sets is written back nowhere. Without an account the
/// probe starts empty (a logged-out search is not captured). The wiki is served logged out (`R54`) and is read without
/// cookies, logged in or not; legacy sent the shared cookies there too (`AnswerView.swift:775`). Answers are decoded as
/// UTF-8 first (`TextDecoding`, Q-2); legacy tried Latin-1 first (`SmileySearchService.swift:32-34`). Nothing is retried,
/// and a task cancelled before the request goes out sends nothing.
public struct SmileyLookupFlow: Sendable {
    private let account: HFRSession?
    private let makeProbe: @Sendable ([StoredCookie]) -> any HTTPTransport
    private let anonymous: any HTTPTransport

    /// Creates a flow that searches with the cookies of `session`, without ever changing it; nil when no account is
    /// logged in (the wiki needs none).
    public init(session: HFRSession? = nil) {
        self.init(session: session, makeProbe: { HFRSession(cookies: $0) }, anonymous: AnonymousTransport())
    }

    /// Creates a flow with another probe factory and cookie-less transport (tests).
    init(
        session: HFRSession?,
        makeProbe: @escaping @Sendable ([StoredCookie]) -> any HTTPTransport,
        anonymous: any HTTPTransport
    ) {
        self.account = session
        self.makeProbe = makeProbe
        self.anonymous = anonymous
    }

    /// The smileys HFR finds for `text`, in the order served, duplicates kept (`R53c` repeats one); empty when HFR finds
    /// none (`R53a`).
    ///
    /// With `requireAll` each word is sent with a leading `+` (legacy `AnswerView.swift:1308-1318`). That only shapes the
    /// request: what HFR does with it is not captured, and `R53c` shows two words OR-ed. Results are never filtered here.
    /// - Throws: `queryTooShort` before any request (`SmileySearchService.swift:19`), `network`, or `page` when the
    ///   answer holds neither a smiley nor HFR's "no result" sentence.
    public func search(_ text: String, requireAll: Bool = false) async throws(SmileyLookupError) -> [ForumSmiley] {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= HFREndpoint.smileySearchMinimumLength else { throw .queryTooShort }
        let probe = makeProbe(await account?.cookies() ?? [])
        let fetcher = PageFetcher(session: probe, anonymous: anonymous)
        let page = try await Self.fetch { () async throws(NetworkError) in try await fetcher.smileySearch(text, requireAll: requireAll) }
        do {
            return try SmileySearchParser.parse(page.text)
        } catch {
            throw .page(error)
        }
    }

    /// The wiki entry of `code` (surrounding white space dropped): its code, image and keywords.
    /// - Throws: `invalidCode` before any request for a blank code, `network`, or `page` when the answer is not the
    ///   entry of `code` (`invalidValue(field: "smiley0")` for another smiley's entry). The page of a code unknown to the
    ///   wiki is not captured.
    public func wiki(code: String) async throws(SmileyLookupError) -> SmileyWikiDetail {
        let code = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !code.isEmpty else { throw .invalidCode }
        let fetcher = PageFetcher(session: anonymous, anonymous: anonymous)
        let page = try await Self.fetch { () async throws(NetworkError) in try await fetcher.smileyWiki(code: code) }
        let detail: SmileyWikiDetail
        do {
            detail = try SmileyWikiDetailParser.parse(page.text)
        } catch {
            throw .page(error)
        }
        guard detail.code == code else { throw .page(.invalidValue(field: "smiley0")) }
        return detail
    }

    private static func fetch(_ request: () async throws(NetworkError) -> RawPage) async throws(SmileyLookupError) -> RawPage {
        do {
            return try await request()
        } catch {
            throw .network(error)
        }
    }
}
