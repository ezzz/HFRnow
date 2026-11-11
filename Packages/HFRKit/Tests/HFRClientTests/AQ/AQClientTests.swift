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
        #expect(request.timeout == 20)
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

/// LOT-055 create: the captured answer (`T50`: status 200, body `1`), the request, and every other outcome `unconfirmed`.
@Suite("AQ client: create")
struct AQCreateTests {
    static func report(
        existingAlertID: Int? = nil, title: String = "Alert title", topicID: Int = 9_900_001, topicTitle: String = "Own topic subject",
        pseudo: String = "User1", postID: Int = 99_100_001, comment: String = "post de user1",
        postURLSuffix: String = ""
    ) -> AQNewReport {
        let permalink = "https://forum.hardware.fr/hfr/own-category/own-subcategory/"
            + "own-topic-subject-sujet_9900001_1.htm#t99100001" + postURLSuffix
        return AQNewReport(
            existingAlertID: existingAlertID, title: title, topicID: topicID, topicTitle: topicTitle, pseudo: pseudo, postID: postID,
            postURL: URL(string: permalink) ?? URL(fileURLWithPath: "/"), comment: comment)
    }

    static func text(_ data: Data?) -> String {
        String(data: data ?? Data(), encoding: .utf8) ?? ""
    }

    static func created() throws -> (AQClient, MockTransport) {
        let body = try AQClientTests.capture("T50-aq-create-answer.txt")
        return try AQClientTests.client { request async throws(NetworkError) -> HTTPResponse in
            HTTPResponse(statusCode: 200, headers: ["Content-Type": "text/plain;charset=UTF-8"], url: request.url, body: body)
        }
    }

    @Test("create: T50's answer is a success; one cookie-less POST of the legacy fields, no redirect, 5 s")
    func createSucceedsOnCapturedAnswer() async throws {
        let (client, transport) = try Self.created()
        try await client.create(Self.report())
        let requests = await transport.requests
        #expect(requests.count == 1)
        let request = try #require(requests.first)
        #expect(request.url.absoluteString == "https://aq.super-h.fr/api/addAlerte.php")
        #expect(request.method == .post)
        #expect(request.headers["Cookie"] == nil)
        #expect(request.headers["Content-Type"] == FormBody.contentType)
        #expect(request.redirectPolicy == .doNotFollow)
        #expect(request.timeout == 5)
        let body = Self.text(request.body)
        let names = body.split(separator: "&").map { $0.split(separator: "=", maxSplits: 1)[0] }
        #expect(names == ["alerte_qualitay_id", "nom", "topic_id", "topic_titre", "pseudo", "post_id", "post_url", "commentaire", "from"])
        #expect(body.hasPrefix(
            "alerte_qualitay_id=-1&nom=Alert+title&topic_id=9900001&topic_titre=Own+topic+subject&pseudo=user1&post_id=99100001"))
        #expect(body.hasSuffix("&from=SwiftHFR"))
        #expect(body.contains("post_url=https%3A%2F%2Fforum.hardware.fr%2Fhfr%2F"))
    }

    @Test("create: an addition sends the AQ id and no title or topic fields")
    func additionFields() async throws {
        let (client, transport) = try Self.created()
        try await client.create(Self.report(existingAlertID: 13_636, title: "", topicTitle: ""))
        let body = Self.text(await transport.requests.first?.body)
        #expect(body.hasPrefix("alerte_qualitay_id=13636&pseudo=user1&post_id="))
        #expect(!body.contains("nom=") && !body.contains("topic_id=") && !body.contains("topic_titre="))
    }

    @Test("create: anything but 200 with `1` is unconfirmed, never a success", arguments: [
        (200, ""), (200, "11"), (200, "-1"), (200, "-4"), (200, "<html>ok</html>"), (403, ""), (201, "1"), (500, "1")
    ])
    func otherAnswersAreUnconfirmed(status: Int, body: String) async throws {
        let (client, transport) = try AQClientTests.client(AQClientTests.reply(status: status, body: body))
        do {
            try await client.create(Self.report())
            Issue.record("a non-confirmed answer was read as a success")
        } catch {
            guard case .unconfirmed(.unrecognizedAnswer(let code, _)) = error else { Issue.record("wrong error \(error)"); return }
            #expect(code == status)
        }
        #expect(await transport.requests.count == 1)
    }

    @Test("create: a numeric code is carried, a page is not")
    func codeIsCarriedWhenBare() async throws {
        let (coded, _) = try AQClientTests.client(AQClientTests.reply(status: 200, body: "-4\n"))
        let four = AQCreateError.unconfirmed(.unrecognizedAnswer(statusCode: 200, code: "-4"))
        await #expect(throws: four) { try await coded.create(Self.report()) }
        let (page, _) = try AQClientTests.client(AQClientTests.reply(status: 200, body: "<html>1</html>"))
        let none = AQCreateError.unconfirmed(.unrecognizedAnswer(statusCode: 200, code: nil))
        await #expect(throws: none) { try await page.create(Self.report()) }
    }

    @Test("create: a redirect and a transport failure are unconfirmed, and the POST is not retried")
    func redirectAndTransport() async throws {
        let location: HTTPHeaders = ["Location": "https://forum.hardware.fr/"]
        let (moved, movedTransport) = try AQClientTests.client(AQClientTests.reply(status: 302, headers: location))
        await #expect(throws: AQCreateError.unconfirmed(.redirected(statusCode: 302))) { try await moved.create(Self.report()) }
        #expect(await movedTransport.requests.count == 1)
        let (slow, slowTransport) = try AQClientTests.client { _ async throws(NetworkError) -> HTTPResponse in throw .timedOut }
        await #expect(throws: AQCreateError.unconfirmed(.transport(.timedOut))) { try await slow.create(Self.report()) }
        #expect(await slowTransport.requests.count == 1)
    }

    @Test("create: a report the database would refuse or change is refused before any request", arguments: [
        (Self.report(comment: String(repeating: "a", count: 1025)), AQReportProblem.tooLong(.comment)),
        (Self.report(comment: "ok 😀"), .unsupportedCharacters(.comment)),
        (Self.report(title: "AQ 😀"), .unsupportedCharacters(.title)),
        (Self.report(title: "0"), .missing(.title)),
        (Self.report(title: "  "), .missing(.title)),
        (Self.report(topicTitle: ""), .missing(.topicTitle)),
        (Self.report(pseudo: ""), .missing(.pseudo)),
        (Self.report(pseudo: String(repeating: "p", count: 129)), .tooLong(.pseudo)),
        (Self.report(pseudo: String(repeating: "İ", count: 65)), .tooLong(.pseudo)),
        (Self.report(title: String(repeating: "t", count: 513)), .tooLong(.title)),
        (Self.report(topicTitle: String(repeating: "t", count: 513)), .tooLong(.topicTitle)),
        (Self.report(postURLSuffix: String(repeating: "x", count: 513)), .tooLong(.postURL)),
        (Self.report(topicID: 0), .outOfRange(.topicID)),
        (Self.report(postID: Int(Int32.max) + 1), .outOfRange(.postID)),
        (Self.report(existingAlertID: 0), .outOfRange(.existingAlertID))
    ])
    func invalidReports(report: AQNewReport, problem: AQReportProblem) async throws {
        let (client, transport) = try Self.created()
        await #expect(throws: AQCreateError.invalidReport(problem)) { try await client.create(report) }
        #expect(await transport.requests.isEmpty)
    }

    @Test("create: a task cancelled before sending is `cancelled` (nothing sent), not unconfirmed")
    func cancelledBeforeSending() async throws {
        let (client, transport) = try Self.created()
        let task = Task { () async -> AQCreateError? in
            withUnsafeCurrentTask { $0?.cancel() }
            do throws(AQCreateError) { try await client.create(Self.report()) } catch { return error }
            return nil
        }
        #expect(await task.value == .cancelled)
        #expect(await transport.requests.isEmpty)
    }

    @Test("create: a 1024-character comment is accepted (T74); a permalink off forum.hardware.fr is refused")
    func boundariesAndPermalink() async throws {
        let (client, transport) = try Self.created()
        try await client.create(Self.report(comment: String(repeating: "é", count: 1024)))
        #expect(await transport.requests.count == 1)
        var other = Self.report()
        other.postURL = URL(string: "http://forum.hardware.fr/hfr/x_1_1.htm#t1") ?? other.postURL
        await #expect(throws: AQCreateError.invalidReport(.notForumPermalink)) { try await client.create(other) }
        #expect(await transport.requests.count == 1)
    }

    @Test("create: an addition may leave title and topic empty (T84) but still needs a pseudo (T83)")
    func additionRules() async throws {
        let (client, _) = try Self.created()
        await #expect(throws: AQCreateError.invalidReport(.missing(.pseudo))) {
            try await client.create(Self.report(existingAlertID: 1, pseudo: ""))
        }
    }
}
