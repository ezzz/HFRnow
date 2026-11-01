import Foundation
import HFRModels
import Testing
@testable import HFRNetwork

/// `HFRSession.probe(cookies:now:)` (#320): a fresh jar that keeps the source session's host policy. Offline.
struct HFRSessionProbeTests {
    private static let now = Date()
    private static let cookie = StoredCookie(
        name: "md_user", value: "user1", domain: ".hardware.fr", path: "/", expiresDate: now.addingTimeInterval(86_400)
    )

    @Test func aProbeKeepsTheHostPolicyAndHoldsOnlyItsSeed() async {
        let restricted = HFRSession(
            cookies: [], hashCheck: "token", now: Self.now, configuration: .ephemeral, hosts: .exactHost("127.0.0.1")
        )
        let probe = restricted.probe(cookies: [Self.cookie], now: Self.now)
        #expect(await probe.hosts == .exactHost("127.0.0.1"))
        // The jar rounds expiries to the second: compare what identifies a cookie.
        #expect(await probe.cookies(now: Self.now).map { "\($0.name)=\($0.value)" } == ["md_user=user1"])
        #expect(await probe.hashCheck == nil)
        // Its own jar: the source session is untouched.
        #expect(await restricted.cookies(now: Self.now).isEmpty)
        #expect(await HFRSession().probe(cookies: [], now: Self.now).hosts == .forum)
    }

    /// On Linux `URLSession.configuration` is one stored object: a probe must not write the source's jar into it.
    @Test func aProbeLeavesTheSourceConfigurationAlone() async {
        let source = HFRSession(cookies: [], hashCheck: nil, now: Self.now, configuration: .ephemeral, hosts: .forum)
        let probe = source.probe(cookies: [Self.cookie], now: Self.now)
        #expect(await source.configurationHoldsItsOwnJar())
        #expect(await probe.configurationHoldsItsOwnJar())
    }
}
