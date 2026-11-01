import Foundation
import HFRModels
import Testing
@testable import HFRClient
@testable import HFRNetwork

/// #365: the default probe of the MP poll, the smiley search and the login keeps the source session's host policy, as
/// `SessionRefreshFlow`'s does (#320). Checked offline: each probe is built, never sent (LESSONS 56).
struct ProbeHostPolicyTests {
    private static let now = Date()
    private static let loopback = SessionHostPolicy.exactHost("127.0.0.1")

    private static let cookie = StoredCookie(
        name: "md_user", value: "user1", domain: ".hardware.fr", path: "/", expiresDate: now.addingTimeInterval(86_400)
    )

    /// The jar rounds expiries to the second: compare what identifies a cookie.
    private static func seed(of probe: HFRSession?) async -> [String]? {
        await probe?.cookies(now: now).map { "\($0.name)=\($0.value)" }
    }

    private static func restricted() -> HFRSession {
        HFRSession(cookies: [], hashCheck: nil, now: now, configuration: .ephemeral, hosts: loopback)
    }

    @Test func theMPPollProbeKeepsTheAccountHostPolicy() async {
        let probe = MPUnreadPoll(session: Self.restricted()).probe(cookies: [Self.cookie]) as? HFRSession
        #expect(await probe?.hosts == Self.loopback)
        #expect(await Self.seed(of: probe) == ["md_user=user1"])
        let production = MPUnreadPoll(session: HFRSession()).probe(cookies: []) as? HFRSession
        #expect(await production?.hosts == .forum)
    }

    @Test func theSmileySearchProbeKeepsTheAccountHostPolicy() async {
        let probe = SmileyLookupFlow(session: Self.restricted()).probe(cookies: [Self.cookie]) as? HFRSession
        #expect(await probe?.hosts == Self.loopback)
        #expect(await Self.seed(of: probe) == ["md_user=user1"])
        // Without an account there is no policy to keep: the forum's.
        let anonymous = SmileyLookupFlow(session: nil).probe(cookies: []) as? HFRSession
        #expect(await anonymous?.hosts == .forum)
    }

    @Test func theLoginJarKeepsTheTargetSessionHostPolicyAndStartsEmpty() async {
        let session = Self.restricted()
        await session.mergeCookies([Self.cookie], now: Self.now)
        let jar = LoginFlow().jar(for: session, now: Self.now) as? HFRSession
        #expect(await jar?.hosts == Self.loopback)
        #expect(await jar?.cookies(now: Self.now).isEmpty == true)
        let production = LoginFlow().jar(for: HFRSession(), now: Self.now) as? HFRSession
        #expect(await production?.hosts == .forum)
    }
}
