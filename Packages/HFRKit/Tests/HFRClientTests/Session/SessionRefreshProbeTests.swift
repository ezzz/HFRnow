import Foundation
import HFRModels
import Testing
@testable import HFRClient
@testable import HFRNetwork

/// #320: without a test factory, `SessionRefreshFlow` probes through a session with the refreshed session's host policy.
/// Checked offline: the probe is built, never sent.
struct SessionRefreshProbeTests {
    @Test func theDefaultProbeKeepsTheRefreshedSessionHostPolicy() async {
        let now = Date()
        let restricted = HFRSession(
            cookies: [], hashCheck: nil, now: now, configuration: .ephemeral, hosts: .exactHost("127.0.0.1")
        )
        let probe = SessionRefreshFlow().probe(for: restricted, cookies: [], now: now) as? HFRSession
        #expect(await probe?.hosts == .exactHost("127.0.0.1"))
        let production = SessionRefreshFlow().probe(for: HFRSession(), cookies: [], now: now) as? HFRSession
        #expect(await production?.hosts == .forum)
    }
}
