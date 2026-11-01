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

    private static func restricted() -> HFRSession {
        HFRSession(cookies: [], hashCheck: nil, now: now, configuration: .ephemeral, hosts: loopback)
    }

    @Test func theMPPollProbeKeepsTheAccountHostPolicy() async {
        let probe = MPUnreadPoll(session: Self.restricted()).probe(cookies: []) as? HFRSession
        #expect(await probe?.hosts == Self.loopback)
        let production = MPUnreadPoll(session: HFRSession()).probe(cookies: []) as? HFRSession
        #expect(await production?.hosts == .forum)
    }

    @Test func theSmileySearchProbeKeepsTheAccountHostPolicy() async {
        let probe = SmileyLookupFlow(session: Self.restricted()).probe(cookies: []) as? HFRSession
        #expect(await probe?.hosts == Self.loopback)
        // Without an account there is no policy to keep: the forum's.
        let anonymous = SmileyLookupFlow(session: nil).probe(cookies: []) as? HFRSession
        #expect(await anonymous?.hosts == .forum)
    }

    @Test func theLoginJarKeepsTheTargetSessionHostPolicyAndStartsEmpty() async {
        let session = Self.restricted()
        let expiry = Self.now.addingTimeInterval(86_400)
        await session.mergeCookies(
            [StoredCookie(name: "md_user", value: "user1", domain: ".hardware.fr", path: "/", expiresDate: expiry)], now: Self.now
        )
        let jar = LoginFlow().jar(for: session, now: Self.now) as? HFRSession
        #expect(await jar?.hosts == Self.loopback)
        #expect(await jar?.cookies(now: Self.now).isEmpty == true)
        let production = LoginFlow().jar(for: HFRSession(), now: Self.now) as? HFRSession
        #expect(await production?.hosts == .forum)
    }
}
