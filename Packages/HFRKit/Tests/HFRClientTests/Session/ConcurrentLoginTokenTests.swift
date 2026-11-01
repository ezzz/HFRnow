import Foundation
import HFRModels
import HFRNetwork
import Testing
@testable import HFRClient

/// Issue #308: a page's `hash_check` never overwrites the token of a login adopted while the page was in flight.
@Suite("The token of a concurrent login wins over a page's")
struct ConcurrentLoginTokenTests {
    static let cuisine = TopicID(category: .forum(13), topic: 28563)
    /// What `adoptLogin` installs: the token read with the new cookies (fake value).
    static let fresher = "fresher-token-0456"

    /// A whole second one day ahead: Darwin keeps such an expiry intact (LOT-042 learnings).
    private let now = Date(timeIntervalSince1970: Date().timeIntervalSince1970.rounded(.down))

    private func cookies(user: String) -> [StoredCookie] {
        let expiry = now.addingTimeInterval(86_400)
        return [
            StoredCookie(name: "md_user", value: user, domain: ".hardware.fr", path: "/", expiresDate: expiry),
            StoredCookie(name: "md_passs", value: "fakepass", domain: ".hardware.fr", path: "/", expiresDate: expiry)
        ]
    }

    // MARK: - Flows

    @Test(
        "A read mark keeps the token of a login adopted during its GET (R21)",
        arguments: [ConcurrentLogin(identity: "user1", hashCheck: fresher), ConcurrentLogin(identity: "user2", hashCheck: fresher)]
    )
    func markReadKeepsFresherToken(login: ConcurrentLogin) async throws {
        let session = ScriptedFlagSession([try FlagCapture.page("R21")], hashCheck: "old-token-0123")
        await session.adoptLoginDuringNextRequest(login)
        let mark = try await TopicFlagFlow().markRead(Self.cuisine, page: 1, through: session)
        #expect(mark.topic == Self.cuisine)
        #expect(await session.hashCheck == Self.fresher)
        #expect(await session.hashChecks.isEmpty)
    }

    @Test(
        "A loaded form keeps the token of a login adopted during its GET (R40a)",
        arguments: [ConcurrentLogin(identity: "user1", hashCheck: fresher), ConcurrentLogin(identity: "user2", hashCheck: fresher)]
    )
    func loadFormKeepsFresherToken(login: ConcurrentLogin) async throws {
        let session = ScriptedPostingSession([try PostingCapture.form("R40a")])
        await session.adoptLoginDuringNextRequest(login)
        _ = try await PostingFlow().loadForm(at: try PostingCapture.pageURL("R40a"), through: session)
        #expect(await session.hashCheck == Self.fresher)
        #expect(await session.hashChecks.isEmpty)
    }

    @Test("Without a concurrent login, the form's token is recorded (R40a)")
    func loadFormRecordsToken() async throws {
        let session = ScriptedPostingSession([try PostingCapture.form("R40a")])
        _ = try await PostingFlow().loadForm(at: try PostingCapture.pageURL("R40a"), through: session)
        #expect(await session.hashCheck == "REDACTED")
        #expect(await session.hashChecks == ["REDACTED"])
    }

    // MARK: - HFRSession

    @Test("On a real session, a token is recorded only while identity and token are those of the seed")
    func compareAndSetOnHFRSession() async throws {
        let session = HFRSession(cookies: cookies(user: "user1"), hashCheck: "old-token-0123", now: now)
        let seed = await session.hashCheckSeed(now: now)
        #expect(await session.updateHashCheck("page-token-0789", since: seed, now: now))
        #expect(await session.hashCheck == "page-token-0789")
    }

    @Test(
        "On a real session, a re-login, an account switch or a logout after the seed keeps the session's state",
        arguments: ["relogin", "switch", "logout"]
    )
    func changeAfterSeedWins(change: String) async throws {
        let session = HFRSession(cookies: cookies(user: "user1"), hashCheck: "old-token-0123", now: now)
        let seed = await session.hashCheckSeed(now: now)
        switch change {
        case "relogin":
            try await session.adoptLogin(cookies: cookies(user: "user1"), hashCheck: Self.fresher, now: now)
        case "switch":
            try await session.adoptLogin(cookies: cookies(user: "user2"), hashCheck: Self.fresher, now: now)
        default:
            // A logout empties the jar and keeps the token: only the identity tells the change.
            await session.removeAllCookies()
        }
        let expected = change == "logout" ? "old-token-0123" : Self.fresher
        #expect(await session.updateHashCheck("page-token-0789", since: seed, now: now) == false)
        #expect(await session.hashCheck == expected)
    }
}
