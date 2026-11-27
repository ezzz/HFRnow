import Foundation
import HFRModels
import Testing
@testable import HFRClient
@testable import HFRNetwork

/// #1398: the session checks, the MP poll and a gated write's check of one account send through one recycled probe
/// connection, not a new `URLSession` each. Offline: the account is restricted to the loopback host, so every probe's
/// forum request is refused before it leaves (LESSONS 56) and its connection goes back to the pool.
struct ProbeConnectionReuseTests {
    private static let now = Date()

    private static func account() -> HFRSession {
        let identity = StoredCookie(
            name: "md_user", value: "user1", domain: ".hardware.fr", path: "/", expiresDate: now.addingTimeInterval(86_400)
        )
        return HFRSession(
            cookies: [identity], hashCheck: "token", now: now, configuration: .ephemeral, hosts: .exactHost("127.0.0.1")
        )
    }

    @Test func refreshesPollsAndAGatedWriteOpenOneProbeConnection() async throws {
        let account = Self.account()
        for _ in 0..<3 {
            await #expect(throws: NetworkError.self) { try await SessionRefreshFlow().refresh(account) }
        }
        await #expect(throws: MPUnreadPollError.self) { try await MPUnreadPoll(session: account).unreadCount() }
        let link = try #require(URL(string: "https://forum.hardware.fr/user/addflag.php?config=hfr.inc&cat=13&post=1"))
        await #expect(throws: TopicFlagError.self) { try await TopicFlagFlow().addFavorite(link: link, in: account) }
        #expect(account.probeConnections.connectionsCreated == 1)
    }
}
