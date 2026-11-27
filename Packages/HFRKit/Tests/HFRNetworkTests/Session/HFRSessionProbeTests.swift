import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
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

/// Probes recycle their connection (#1398): a check, a poll or a gated write's check no longer opens a new `URLSession`
/// each time, and a recycled connection carries nothing of the probe that used it before. Loopback only.
struct HFRSessionProbeConnectionTests {
    private static func proxyless() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        return configuration
    }

    private static func makeSource() -> HFRSession {
        HFRSession(cookies: [], hashCheck: nil, now: Date(), configuration: proxyless(), hosts: .exactHost("127.0.0.1"))
    }

    private static func localCookie(_ name: String, _ value: String) -> StoredCookie {
        StoredCookie(name: name, value: value, domain: "127.0.0.1", path: "/")
    }

    /// `/set/<v>` answers `Set-Cookie: sid=<v>`; `/slow` never answers; anything else an empty page.
    private static func makeServer() throws -> LoopbackServer {
        try LoopbackServer { request in
            if request.path == "/slow" { return ServerReply(hangs: true) }
            guard request.path.hasPrefix("/set/") else { return ServerReply() }
            return ServerReply(headers: ["Set-Cookie": "sid=\(request.path.dropFirst("/set/".count)); Path=/"])
        }
    }

    @Test func probesUsedOneAfterTheOtherShareOneConnection() async throws {
        let server = try Self.makeServer()
        defer { server.stop() }
        let source = Self.makeSource()
        for index in 0..<3 {
            let probe = source.probe(cookies: [], now: Date())
            _ = try await probe.send(.get(server.baseURL.appending(path: "check/\(index)")))
        }
        #expect(source.probeConnections.connectionsCreated == 1)
        #expect(source.probeConnections.idleCount == 1)
    }

    @Test func aRecycledConnectionStartsWithOnlyTheNewSeed() async throws {
        let server = try Self.makeServer()
        defer { server.stop() }
        let source = Self.makeSource()
        do {
            let first = source.probe(cookies: [Self.localCookie("seed", "one")], now: Date())
            _ = try await first.send(.get(server.baseURL.appending(path: "set/first")))
        }
        let second = source.probe(cookies: [Self.localCookie("seed", "two")], now: Date())
        #expect(await second.hashCheck == nil)
        #expect(await second.cookies().map { "\($0.name)=\($0.value)" } == ["seed=two"])
        _ = try await second.send(.get(server.baseURL.appending(path: "echo")))
        let header = try #require(server.requests.last { $0.path == "/echo" }?.headers["cookie"])
        #expect(header == "seed=two")
        #expect(source.probeConnections.connectionsCreated == 1)
    }

    @Test func probesAliveTogetherNeverShareAConnection() async throws {
        let server = try Self.makeServer()
        defer { server.stop() }
        let source = Self.makeSource()
        let first = source.probe(cookies: [], now: Date())
        let second = source.probe(cookies: [], now: Date())
        async let setFirst = first.send(.get(server.baseURL.appending(path: "set/one")))
        async let setSecond = second.send(.get(server.baseURL.appending(path: "set/two")))
        _ = try await (setFirst, setSecond)
        #expect(await first.cookies().map(\.value) == ["one"])
        #expect(await second.cookies().map(\.value) == ["two"])
        #expect(source.probeConnections.connectionsCreated == 2)
    }

    @Test func aConnectionWhoseExchangeThrewIsNotRecycled() async throws {
        let server = try Self.makeServer()
        defer { server.stop() }
        let source = Self.makeSource()
        do {
            let probe = source.probe(cookies: [], now: Date())
            var request = HTTPRequest.get(server.baseURL.appending(path: "slow"))
            request.timeout = 0.2
            await #expect(throws: NetworkError.self) { try await probe.send(request) }
        }
        #expect(source.probeConnections.idleCount == 0)
        _ = source.probe(cookies: [], now: Date())
        #expect(source.probeConnections.connectionsCreated == 2)
    }

    @Test func theSourceSessionOpensNoProbeConnectionByItself() async throws {
        let server = try Self.makeServer()
        defer { server.stop() }
        let source = Self.makeSource()
        _ = try await source.send(.get(server.baseURL.appending(path: "page")))
        #expect(source.probeConnections.connectionsCreated == 0)
    }
}

/// The pool itself (#1398): its bounds, its end, and its jars under concurrent release. Offline.
struct ProbeConnectionPoolTests {
    private static func makeSource() -> HFRSession {
        HFRSession(cookies: [], hashCheck: nil, now: Date(), configuration: .ephemeral, hosts: .exactHost("127.0.0.1"))
    }

    /// A probe released on one thread while another takes its connection must not empty the newcomer's seed (round 1, #1412).
    @Test func aRecycledProbeKeepsItsSeedUnderConcurrentRelease() async {
        let source = Self.makeSource()
        let lost = await withTaskGroup(of: Int.self) { group in
            for worker in 0..<8 {
                group.addTask {
                    var lost = 0
                    for index in 0..<1500 {
                        let value = "w\(worker)i\(index)"
                        let seed = (0..<4).map { StoredCookie(name: "seed\($0)", value: value, domain: "127.0.0.1", path: "/") }
                        let probe = source.probe(cookies: seed, now: Date())
                        await Task.yield()
                        if await probe.cookies().map(\.value) != [value, value, value, value] { lost += 1 }
                    }
                    return lost
                }
            }
            var total = 0
            for await count in group { total += count }
            return total
        }
        #expect(lost == 0)
    }

    @Test func thePoolKeepsAtMostItsLimitAndInvalidatesTheRest() {
        let pool = ProbeConnectionPool(configuration: .ephemeral, hosts: .exactHost("127.0.0.1"))
        // Two idle connections per account: enough for a check and a poll at the same time, no more sockets kept open.
        let connections = (0..<3).map { _ in pool.checkOut() }
        for connection in connections { pool.checkIn(connection, reusable: true) }
        #expect(pool.idleCount == 2)
        #expect(connections.map(\.isInvalidated) == [false, false, true])
    }

    @Test func aConnectionNotReusableIsInvalidated() {
        let pool = ProbeConnectionPool(configuration: .ephemeral, hosts: .exactHost("127.0.0.1"))
        let connection = pool.checkOut()
        pool.checkIn(connection, reusable: false)
        #expect(connection.isInvalidated)
        #expect(pool.idleCount == 0)
    }

    @Test func aReleasedPoolInvalidatesItsIdleConnections() {
        var pool: ProbeConnectionPool? = ProbeConnectionPool(configuration: .ephemeral, hosts: .exactHost("127.0.0.1"))
        let connection = pool?.checkOut()
        if let connection { pool?.checkIn(connection, reusable: true) }
        #expect(connection?.isInvalidated == false)
        pool = nil
        #expect(connection?.isInvalidated == true)
    }
}
