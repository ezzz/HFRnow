import Foundation
import HFRModels
import HFRParsing
import Testing
@testable import HFRClient
@testable import HFRNetwork

/// LOT-055: the AQ reads on the captured feed (`T01`) and listing (`T02`), the "new since" count against the legacy
/// oracle, and the third-party rules (LOT-071 R1, R2): configured host only, no cookie, no redirect followed.
@Suite("AQ client")
struct AQClientTests {
    static let base = URL(string: "https://aq.super-h.fr") ?? URL(fileURLWithPath: "/")

    static func capture(_ file: String) throws -> Data {
        let url = Capture.directory.appendingPathComponent(file)
        guard let data = try? Data(contentsOf: url) else { throw Capture.Missing(name: file) }
        return data
    }

    /// A capture served as its meta says (status 200, its content type, no redirect).
    static func served(_ file: String, contentType: String) -> MockTransport.Handler {
        { request async throws(NetworkError) -> HTTPResponse in
            guard let body = try? capture(file) else { throw .unscripted }
            return HTTPResponse(statusCode: 200, headers: ["Content-Type": contentType], url: request.url, body: body)
        }
    }

    static func client(_ handler: @escaping MockTransport.Handler) throws -> (AQClient, MockTransport) {
        let transport = MockTransport(handler: handler)
        return (AQClient(configuration: try AQConfiguration(baseURL: base), transport: transport), transport)
    }

    static func reply(status: Int, body: String = "", headers: HTTPHeaders = [:]) -> MockTransport.Handler {
        { request async throws(NetworkError) -> HTTPResponse in
            HTTPResponse(statusCode: status, headers: headers, url: request.url, body: Data(body.utf8))
        }
    }

    // MARK: - Feed

    @Test("feed: one GET of /rss.php on the configured host, every T01 item kept with its category")
    func feedRequestAndItems() async throws {
        let (client, transport) = try Self.client(Self.served("T01-aq-rss-feed.xml", contentType: "application/rss+xml;charset=utf-8"))
        let items = try await client.feed()
        #expect(items.count == 25)
        // Every category is returned (Q-7 is app policy): 23 links carry a `cat`, the 2 canonical paths none (LOT-028).
        #expect(items.compactMap(AQFeedParser.category(of:)).count == 23)
        let requests = await transport.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.url.absoluteString == "https://aq.super-h.fr/rss.php")
        #expect(request.method == .get)
        #expect(request.body == nil)
        #expect(request.headers["Cookie"] == nil)
        #expect(request.redirectPolicy == .doNotFollow)
        #expect(request.timeout == AQClient.timeout)
        #expect(request.maximumBodyBytes == AQClient.maximumResponseBytes)
    }

    @Test("feed: the new count on T01 is the legacy oracle's (2 since 2026-10-01)")
    func newCountMatchesOracle() async throws {
        let (client, _) = try Self.client(Self.served("T01-aq-rss-feed.xml", contentType: "application/rss+xml;charset=utf-8"))
        let items = try await client.feed()
        let lastCheck = try Date("2026-10-01T00:00:00Z", strategy: .iso8601)
        let oracle = try Self.oracleNewFlags()
        // Legacy counted after hiding category 25; T01 has no such item, so the visible list is the whole feed.
        #expect(items.map { AQClient.isNew($0, since: lastCheck) } == oracle)
        #expect(AQClient.newCount(in: items, since: lastCheck) == 2)
    }

    @Test("new since: the boundary is inclusive and an undated item is never new")
    func newSinceRules() throws {
        let link = try #require(URL(string: "https://forum.hardware.fr/forum2.php?post=1"))
        let instant = Date(timeIntervalSince1970: 1_800_000_000)
        func item(_ date: Date?) -> AQFeedItem {
            AQFeedItem(topicTitle: "t", title: "a", comment: "c", initiator: "user1", publishedAt: date, link: link)
        }
        #expect(AQClient.isNew(item(instant), since: instant))
        #expect(!AQClient.isNew(item(instant.addingTimeInterval(-1)), since: instant))
        #expect(!AQClient.isNew(item(nil), since: .distantPast))
        #expect(AQClient.newCount(in: [item(nil), item(instant), item(.distantPast)], since: instant) == 1)
    }

    // MARK: - Per-topic check

    @Test("check: one GET of getAlertesByTopic.php?topic_id=, T02 parsed, whole-number match")
    func checkRequestAndAnswer() async throws {
        let (client, transport) = try Self.client(Self.served("T02-aq-alerts-by-topic.xml", contentType: "text/xml;charset=UTF-8"))
        #expect(try await client.isReported(postID: 75_396_914, topicID: 8680))
        #expect(try await !client.isReported(postID: 7_539_691, topicID: 8680))
        #expect(try await client.alerts(topicID: 8680).count == 123)
        let requests = await transport.requests
        #expect(requests.count == 3)
        for request in requests {
            #expect(request.url.absoluteString == "https://aq.super-h.fr/api/getAlertesByTopic.php?topic_id=8680")
            #expect(request.method == .get)
            #expect(request.headers["Cookie"] == nil)
            #expect(request.redirectPolicy == .doNotFollow)
        }
    }

    @Test("check: a topic number that is not positive is refused before any request")
    func invalidTopic() async throws {
        let (client, transport) = try Self.client(Self.reply(status: 200))
        await #expect(throws: AQError.invalidTopicID) { try await client.alerts(topicID: 0) }
        await #expect(throws: AQError.invalidTopicID) { try await client.isReported(postID: 1, topicID: -3) }
        #expect(await transport.requests.isEmpty)
    }

    // MARK: - Failures are never "nothing"

    @Test("a redirect is not followed and is an error, whatever its target")
    func redirectIsError() async throws {
        for status in [301, 302, 303, 307, 308] {
            let (client, _) = try Self.client(Self.reply(status: status, headers: ["Location": "https://forum.hardware.fr/"]))
            await #expect(throws: AQError.redirected(statusCode: status)) { try await client.feed() }
            await #expect(throws: AQError.redirected(statusCode: status)) { try await client.alerts(topicID: 8680) }
        }
    }

    @Test("4xx/5xx, a transport failure and a non-AQ body are errors, never an empty list")
    func failures() async throws {
        let (notFound, _) = try Self.client(Self.reply(status: 404, body: "<alertes/>"))
        await #expect(throws: AQError.http(statusCode: 404)) { try await notFound.alerts(topicID: 8680) }
        let (offline, _) = try Self.client { _ async throws(NetworkError) -> HTTPResponse in throw .offline }
        await #expect(throws: AQError.network(.offline)) { try await offline.feed() }
        let (html, _) = try Self.client(Self.reply(status: 200, body: "<html><body>Erreur</body></html>"))
        await #expect(throws: AQError.self) { try await html.feed() }
        await #expect(throws: AQError.self) { try await html.isReported(postID: 1, topicID: 8680) }
        // The other AQ document is not this one's answer.
        let (swapped, _) = try Self.client(Self.served("T02-aq-alerts-by-topic.xml", contentType: "text/xml;charset=UTF-8"))
        await #expect(throws: AQError.self) { try await swapped.feed() }
    }

    // MARK: - Third-party policy (no network path: LESSONS 56)

    @Test("the default transport is the cookie-less one, with cookies off both ways")
    func defaultTransportIsAnonymous() throws {
        let client = AQClient(configuration: try AQConfiguration(baseURL: Self.base))
        #expect(client.transport is AnonymousTransport)
        let configuration = AnonymousTransport.cookieless(.ephemeral)
        #expect(configuration.httpCookieStorage == nil)
        #expect(!configuration.httpShouldSetCookies)
    }

    @Test("base URL: https, or http on loopback; no forum host, userinfo, query or fragment")
    func baseURLRules() throws {
        let accepted = ["https://aq.super-h.fr", "https://aq.super-h.fr/", "http://127.0.0.1:8080", "http://localhost"]
        for text in accepted {
            #expect(throws: Never.self) { try AQConfiguration(baseURL: try #require(URL(string: text))) }
        }
        let refused = [
            "http://aq.super-h.fr", "https://forum.hardware.fr", "https://hardware.fr", "https://FORUM.hardware.fr.",
            "https://user:pw@aq.super-h.fr", "https://aq.super-h.fr/?x=1", "https://aq.super-h.fr/#a", "ftp://aq.super-h.fr"
        ]
        for text in refused {
            #expect(throws: AQError.invalidBaseURL) { try AQConfiguration(baseURL: try #require(URL(string: text))) }
        }
    }

    @Test("URLs keep a base path and add the documented paths only")
    func urlsFromBase() throws {
        let configuration = try AQConfiguration(baseURL: try #require(URL(string: "https://aq.example/sub/")))
        #expect(try configuration.feedURL().absoluteString == "https://aq.example/sub/rss.php")
        #expect(try configuration.alertsURL(topicID: 42).absoluteString == "https://aq.example/sub/api/getAlertesByTopic.php?topic_id=42")
    }

    // MARK: - Oracle

    /// `isNew` of each legacy item of `T01` (`Fixtures/LOT-028/T01.oracle.json`, kind `aq-rss`, last check 2026-10-01).
    static func oracleNewFlags() throws -> [Bool] {
        let url = Capture.directory.deletingLastPathComponent().appendingPathComponent("LOT-028/T01.oracle.json")
        let root = try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        let context = try #require((root["input"] as? [String: Any])?["context"] as? [String: Any])
        #expect(context["lastCheck"] as? String == "2026-10-01T00:00:00Z")
        let rows = try #require((root["result"] as? [String: Any])?["items"] as? [[String: Any]])
        return try rows.map { try #require($0["isNew"] as? Bool) }
    }
}
