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
        #expect(await SessionRefreshFlow.defaultProbe(for: restricted, cookies: [], now: now).hosts == .exactHost("127.0.0.1"))
        #expect(await SessionRefreshFlow.defaultProbe(for: HFRSession(), cookies: [], now: now).hosts == .forum)
    }
}
