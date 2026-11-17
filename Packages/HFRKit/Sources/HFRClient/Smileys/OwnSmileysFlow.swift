import Foundation
import HFRModels
import HFRNetwork
import HFRParsing

/// Reads the member's own created smileys (« Smilies persos », #414): one read-only GET of the profile edit page 5
/// (`R601a`, HFR-PROTOCOL §6c « Smiley page and filtered lists »).
///
/// That page sets the account's cookies again (`R55-p5`), so it runs in an ephemeral probe `HFRSession` seeded with the account's
/// cookies, as `SmileyLookupFlow` does: whatever HFR sets is written back nowhere. Nothing is retried, and a task cancelled
/// before the request goes out sends nothing. Legacy's picker never listed them (`AnswerView.swift:1357-1385` @ 2440d79).
public struct OwnSmileysFlow: Sendable {
    private let account: HFRSession
    private let makeProbe: (@Sendable ([StoredCookie]) -> any HTTPTransport)?

    /// Creates a flow that reads with the cookies of `session`, without ever changing it.
    public init(session: HFRSession) {
        self.account = session
        self.makeProbe = nil
    }

    /// Creates a flow with another probe factory (tests).
    init(session: HFRSession, makeProbe: @escaping @Sendable ([StoredCookie]) -> any HTTPTransport) {
        self.account = session
        self.makeProbe = makeProbe
    }

    /// The smileys the member created, empty when there are none.
    /// - Throws: `network`, or `page` when the answer has no « Smilies persos » row (a logged-out or another page).
    public func load() async throws(SmileyLookupError) -> [OwnSmiley] {
        let cookies = await account.cookies()
        let probe: any HTTPTransport = makeProbe?(cookies) ?? account.probe(cookies: cookies, now: Date())
        let page: RawPage
        do {
            page = try await PageFetcher(session: probe).profileEdit(page: .hashAndAvatar)
        } catch {
            throw .network(error)
        }
        do {
            return try OwnSmileysParser.parse(page.text)
        } catch {
            throw .page(error)
        }
    }
}
