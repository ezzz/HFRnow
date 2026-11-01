import Foundation
import HFRModels
import HFRNetwork
import HFRParsing
import Testing
@testable import HFRClient

/// LOT-053: the smiley search over `R53a`-`R53c` and the wiki over `R54`, against the LOT-005 legacy oracles.
@Suite("Smiley search and wiki (LOT-053)")
struct SmileyLookupFlowTests {
    private static let cookies = [
        StoredCookie(name: "md_user", value: "fakeuser", domain: ".hardware.fr", path: "/", expiresDate: Date().addingTimeInterval(86_400)),
        StoredCookie(name: "md_passs", value: "fakepass", domain: ".hardware.fr", path: "/", expiresDate: Date().addingTimeInterval(86_400))
    ]
    private static let searchURL = URL(string: "https://forum.hardware.fr/message-smi-mp-aj.php") ?? URL(fileURLWithPath: "/")

    /// What the probe factory was given.
    final class Seeds: @unchecked Sendable {
        private let lock = NSLock()
        private var all: [[StoredCookie]] = []
        func add(_ cookies: [StoredCookie]) { lock.lock(); all.append(cookies); lock.unlock() }
        var values: [[StoredCookie]] { lock.lock(); defer { lock.unlock() }; return all }
    }

    /// A flow with its scripted probe and cookie-less transport, and the account session it reads.
    struct Ready {
        let flow: SmileyLookupFlow
        let probe: MockTransport
        let anonymous: MockTransport
        let seeds: Seeds
        let account: HFRSession
    }

    private static func flow(
        probe: [Result<HTTPResponse, NetworkError>] = [], anonymous: [Result<HTTPResponse, NetworkError>] = []
    ) -> Ready {
        let account = HFRSession(cookies: cookies)
        let probeTransport = MockTransport(replies: probe)
        let anonymousTransport = MockTransport(replies: anonymous)
        let seeds = Seeds()
        let flow = SmileyLookupFlow(
            session: account, makeProbe: { seeds.add($0); return probeTransport }, anonymous: anonymousTransport
        )
        return Ready(flow: flow, probe: probeTransport, anonymous: anonymousTransport, seeds: seeds, account: account)
    }

    /// The capture `file` served with Set-Cookie, so a write-back would show.
    private static func served(_ file: String, url: URL = searchURL) throws -> Result<HTTPResponse, NetworkError> {
        var response = try Capture.response(file, url: url)
        response.headers["Set-Cookie"] = "md_passs=changed; path=/; domain=.hardware.fr"
        return .success(response)
    }

    @Test(
        "R53a-R53c: the oracle's smileys in order, duplicates kept; the request is the legacy live one; R53a is empty",
        arguments: [
            ("R53a", "R53a-smiley-search-no-result"),
            ("R53b", "R53b-smiley-search-one-word"),
            ("R53c", "R53c-smiley-search-two-words")
        ]
    )
    func searchMatchesTheOracle(id: String, file: String) async throws {
        let oracle = try Lot005Oracle.search(id)
        let ready = Self.flow(probe: [try Self.served(file)])
        let smileys = try await ready.flow.search(oracle.query)
        #expect(smileys.map(\.code) == oracle.items.map(\.code))
        #expect(smileys.map(\.url.absoluteString) == oracle.items.map(\.source))
        let requests = await ready.probe.requests
        #expect(requests.map(\.url.absoluteString) == [oracle.liveRequest])
        #expect(requests.first?.method == .get)
        #expect(await ready.anonymous.requests.isEmpty)
    }

    @Test("R53c: requireAll only shapes the request; the OR-ed answer is returned whole")
    func requireAllDoesNotFilter() async throws {
        let ready = Self.flow(probe: [try Self.served("R53c-smiley-search-two-words")])
        let smileys = try await ready.flow.search("chat noir", requireAll: true)
        #expect(smileys.count == 1010)
        #expect(Set(smileys.map(\.code)).count == 1009)
        let sent = await ready.probe.requests.map(\.url.absoluteString)
        #expect(sent == ["https://forum.hardware.fr/message-smi-mp-aj.php?config=hfr.inc&findsmilies=%2Bchat%20%2Bnoir"])
    }

    @Test("Under 3 characters once trimmed, nothing is sent", arguments: ["", "ab", "  ab \n", "\u{00A0}a\t"])
    func shortTextSendsNothing(text: String) async {
        let ready = Self.flow()
        await #expect(throws: SmileyLookupError.queryTooShort) { try await ready.flow.search(text) }
        #expect(ready.seeds.values.isEmpty)
        #expect(await ready.probe.requests.isEmpty)
    }

    @Test("The search reads the account's cookies through a probe and writes nothing back")
    func searchLeavesTheAccountUnchanged() async throws {
        let ready = Self.flow(probe: [try Self.served("R53b-smiley-search-one-word")])
        let before = await ready.account.cookies()
        _ = try await ready.flow.search("chat")
        #expect(ready.seeds.values == [before])
        #expect(await ready.account.cookies() == before)
    }

    @Test("R54: the oracle's code and keywords; the captured URL; no cookie, on the cookie-less transport")
    func wikiMatchesTheOracle() async throws {
        let meta = try Capture.meta("R54")
        let url = try #require(URL(string: meta.url))
        let ready = Self.flow(anonymous: [try Self.served("R54-smiley-wiki-detail-anon", url: url)])
        let oracle = try Lot005Oracle.wiki("R54")
        let detail = try await ready.flow.wiki(code: oracle.code)
        #expect(detail.code == oracle.code)
        #expect(detail.keywords == oracle.keywords)
        let requests = await ready.anonymous.requests
        #expect(requests.map(\.url.absoluteString) == [meta.url])
        #expect(requests.allSatisfy { $0.headers["Cookie"] == nil })
        #expect(await ready.probe.requests.isEmpty)
        #expect(ready.seeds.values.isEmpty)
    }

    @Test("Another smiley's entry, a blank code, an unreadable page or a network failure are typed errors")
    func failures() async throws {
        let other = Self.flow(anonymous: [try Self.served("R54-smiley-wiki-detail-anon")])
        await #expect(throws: SmileyLookupError.page(.invalidValue(field: "smiley0"))) { try await other.flow.wiki(code: "[:user4]") }

        let blank = Self.flow()
        await #expect(throws: SmileyLookupError.invalidCode) { try await blank.flow.wiki(code: "  ") }
        #expect(await blank.anonymous.requests.isEmpty)

        let body = Data("<html><body><p>Maintenance</p></body></html>".utf8)
        let maintenance = HTTPResponse(statusCode: 200, url: Self.searchURL, body: body)
        let unreadable = Self.flow(probe: [.success(maintenance)])
        await #expect(throws: SmileyLookupError.self) { try await unreadable.flow.search("chat") }

        let offline = Self.flow(probe: [.failure(.offline)], anonymous: [.failure(.timedOut)])
        await #expect(throws: SmileyLookupError.network(.offline)) { try await offline.flow.search("chat") }
        await #expect(throws: SmileyLookupError.network(.timedOut)) { try await offline.flow.wiki(code: "[:user3]") }
    }

    @Test("A cancelled task sends nothing")
    func cancelledTaskSendsNothing() async {
        let ready = Self.flow()
        let task = Task { () async throws -> [ForumSmiley] in
            withUnsafeCurrentTask { $0?.cancel() }
            return try await ready.flow.search("chat")
        }
        let failure = await task.result.failure as? SmileyLookupError
        #expect(failure == .network(.cancelled))
        #expect(await ready.probe.requests.isEmpty)
    }
}

/// The LOT-005 legacy oracles of the smiley captures, read in place from the parsing tests' fixtures.
private enum Lot005Oracle {
    struct Search {
        let query: String
        let items: [(code: String, source: String)]
        let liveRequest: String
    }

    static func search(_ id: String) throws -> Search {
        let object = try load(id)
        let context = try #require((object["input"] as? [String: Any])?["context"] as? [String: Any])
        let result = try #require(object["result"] as? [String: Any])
        let legacy = try #require((result["legacy"] as? [String: Any])?["items"] as? [[String: Any]])
        let requests = try #require((result["live"] as? [String: Any])?["requests"] as? [[String: Any]])
        return Search(
            query: try #require(context["query"] as? String),
            items: legacy.compactMap { item in
                guard let code = item["code"] as? String, let source = item["source"] as? String else { return nil }
                return (code, source)
            },
            liveRequest: try #require(requests.first?["url"] as? String)
        )
    }

    static func wiki(_ id: String) throws -> (code: String, keywords: [String]) {
        let object = try load(id)
        let context = try #require((object["input"] as? [String: Any])?["context"] as? [String: Any])
        let swift = try #require(((object["result"] as? [String: Any])?["swiftApp"]) as? [String: Any])
        return (try #require(context["code"] as? String), try #require(swift["keywords"] as? [String]))
    }

    private static func load(_ id: String) throws -> [String: Any] {
        let url = Capture.directory.deletingLastPathComponent().appendingPathComponent("LOT-005/\(id).oracle.json")
        return try #require(try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
