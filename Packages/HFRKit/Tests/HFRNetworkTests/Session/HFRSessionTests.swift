import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HFRModels
import Testing
@testable import HFRNetwork

/// Runs `HFRSession` against a loopback server (real sockets and cookie handling, no external network).
struct HFRSessionTests {
    /// Ephemeral configuration ignoring proxy environment variables: the target is 127.0.0.1.
    private static func proxylessConfiguration() -> URLSessionConfiguration {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.connectionProxyDictionary = [:]
        return configuration
    }

    private func makeSession(cookies: [StoredCookie] = [], hashCheck: String? = nil) -> HFRSession {
        HFRSession(
            cookies: cookies, hashCheck: hashCheck, now: Date(),
            configuration: Self.proxylessConfiguration(), hosts: .exactHost("127.0.0.1")
        )
    }

    /// `/set/<v>` answers `Set-Cookie: sid=<v>`; any other path answers an empty page.
    private func makeServer() throws -> LoopbackServer {
        try LoopbackServer { request in
            guard request.path.hasPrefix("/set/") else { return ServerReply() }
            let value = request.path.dropFirst("/set/".count)
            return ServerReply(headers: ["Set-Cookie": "sid=\(value); Path=/"])
        }
    }

    private func cookieHeader(_ server: LoopbackServer, path: String) -> String? {
        server.requests.last { $0.path == path }?.headers["cookie"]
    }

    private func localCookie(_ name: String, _ value: String) -> StoredCookie {
        StoredCookie(name: name, value: value, domain: "127.0.0.1", path: "/")
    }

    // MARK: - Isolation

    @Test func twoSessionsNeverShareCookies() async throws {
        let server = try makeServer()
        defer { server.stop() }
        let first = makeSession(cookies: [localCookie("imported", "a")])
        let second = makeSession()
        let base = server.baseURL
        // Both receive a different `sid` at the same time, then call back.
        async let setFirst = first.send(.get(base.appending(path: "set/one")))
        async let setSecond = second.send(.get(base.appending(path: "set/two")))
        _ = try await (setFirst, setSecond)
        async let echoFirst = first.send(.get(base.appending(path: "echo/first")))
        async let echoSecond = second.send(.get(base.appending(path: "echo/second")))
        _ = try await (echoFirst, echoSecond)

        let firstHeader = try #require(cookieHeader(server, path: "/echo/first"))
        #expect(firstHeader.contains("sid=one"))
        #expect(firstHeader.contains("imported=a"))
        #expect(!firstHeader.contains("two"))
        #expect(cookieHeader(server, path: "/echo/second") == "sid=two")
        #expect(await first.cookies().map(\.name) == ["imported", "sid"])
        #expect(await second.cookies().map(\.value) == ["two"])
        // Nothing leaked into the process-wide jar the legacy app used.
        let leaked = HTTPCookieStorage.shared.cookies(for: base) ?? []
        #expect(!leaked.contains { $0.name == "sid" || $0.name == "imported" })
    }

    @Test func cookiesSetByTheServerAreExported() async throws {
        let server = try makeServer()
        defer { server.stop() }
        let session = makeSession()
        _ = try await session.send(.get(server.baseURL.appending(path: "set/fresh")))
        let exported = await session.cookies()
        #expect(exported.count == 1)
        #expect(exported.first?.name == "sid")
        #expect(exported.first?.value == "fresh")
        #expect(exported.first?.domain == "127.0.0.1")
    }

    // MARK: - Hosts and redirects

    /// Corelibs copies the injected `Cookie` header onto a followed redirect, whatever its host (Fable review of #27).
    @Test func redirectLeavingTheAllowedHostIsNotFollowed() async throws {
        let server = try LoopbackServer { request in
            switch request.path {
            case "/leave":
                // Same server under another host name: reachable, but outside the session's host policy.
                let port = request.headers["host"]?.split(separator: ":").last.map(String.init) ?? ""
                return ServerReply(status: 302, headers: ["Location": "http://localhost:\(port)/landed"])
            case "/stay":
                return ServerReply(status: 302, headers: ["Location": "/stayed"])
            default:
                return ServerReply()
            }
        }
        defer { server.stop() }
        let session = makeSession(cookies: [localCookie("md_user", "fakepseudo")])

        let left = try await session.send(.get(server.baseURL.appending(path: "leave")))
        #expect(left.statusCode == 302)
        #expect(left.redirectLocation?.host == "localhost")
        #expect(!server.requests.contains { $0.path == "/landed" })

        // Positive control: a redirect on the allowed host is still followed, with the cookie.
        let stayed = try await session.send(.get(server.baseURL.appending(path: "stay")))
        #expect(stayed.statusCode == 200)
        #expect(stayed.url.path == "/stayed")
        #expect(server.requests.last { $0.path == "/stayed" }?.headers["cookie"] == "md_user=fakepseudo")
    }

    @Test func requestsOutsideTheAllowedHostsAreRefused() async throws {
        let forum = HFRSession(cookies: [StoredCookie(name: "md_user", value: "fakepseudo", domain: ".hardware.fr")])
        for text in ["https://example.com/", "https://evilhardware.fr/", "https://hardware.fr.example.com/"] {
            let url = try #require(URL(string: text))
            await #expect(throws: NetworkError.self) { try await forum.send(.get(url)) }
        }
        let loopback = makeSession()
        let other = try #require(URL(string: "http://localhost:9/"))
        await #expect(throws: NetworkError.invalidRequest(reason: "An account session only contacts hardware.fr")) {
            try await loopback.send(.get(other))
        }
    }

    // MARK: - Import and export

    @Test func importSkipsExpiredCookiesAndExportRoundTrips() async {
        let now = Date()
        let live = StoredCookie(
            name: "md_user", value: "fake", domain: ".hardware.fr", path: "/",
            expiresDate: now.addingTimeInterval(86_400), isSecure: true, isHTTPOnly: true
        )
        let expired = StoredCookie(name: "old", value: "x", domain: ".hardware.fr", expiresDate: now.addingTimeInterval(-60))
        let session = HFRSession(
            cookies: [live, expired], hashCheck: nil, now: now,
            configuration: Self.proxylessConfiguration(), hosts: .exactHost("127.0.0.1")
        )
        let exported = await session.cookies(now: now)
        #expect(exported.count == 1)
        let first = exported.first
        #expect(first?.name == live.name && first?.domain == live.domain && first?.isSecure == true && first?.isHTTPOnly == true)
        // Foundation may round sub-second expiry dates.
        let delta = (first?.expiresDate?.timeIntervalSince1970 ?? 0) - (live.expiresDate?.timeIntervalSince1970 ?? 0)
        #expect(abs(delta) < 1)
        #expect(await session.cookies(now: now.addingTimeInterval(86_401)).isEmpty)
    }

    @Test func mergeReplacesByKeyAndExpiredDeletes() async {
        let session = makeSession(cookies: [StoredCookie(name: "a", value: "1", domain: ".hardware.fr")])
        let merged = await session.mergeCookies([
            StoredCookie(name: "a", value: "2", domain: "hardware.fr"),
            StoredCookie(name: "b", value: "3", domain: ".hardware.fr")
        ])
        #expect(merged == 2)
        #expect(await session.cookies().map(\.value).sorted() == ["2", "3"])
        let expired = StoredCookie(name: "b", value: "", domain: ".hardware.fr", expiresDate: Date(timeIntervalSince1970: 0))
        #expect(await session.mergeCookies([expired]) == 0)
        #expect(await session.cookies().map(\.name) == ["a"])
        // An empty path is the `/` cookie Foundation stores, so an expired import with it still deletes.
        let emptyPath = StoredCookie(name: "a", value: "", domain: "hardware.fr", path: "", expiresDate: Date(timeIntervalSince1970: 0))
        #expect(await session.mergeCookies([emptyPath]) == 0)
        #expect(await session.cookies().isEmpty)
        #expect(await session.replaceCookies(with: [StoredCookie(name: "c", value: "4", domain: ".hardware.fr")]) == 1)
        #expect(await session.cookies().map(\.name) == ["c"])
        await session.removeAllCookies()
        #expect(await session.cookies().isEmpty)
    }

    // MARK: - Identity

    @Test func identityComesFromMdUser() async {
        let session = makeSession()
        #expect(await session.userKey() == nil)
        await session.mergeCookies([StoredCookie(name: "md_user", value: "fakepseudo", domain: ".hardware.fr")])
        #expect(await session.userKey() == "fakepseudo")
        #expect(await session.isLoggedIn())
        await session.mergeCookies([StoredCookie(name: "md_user", value: "deleted", domain: ".hardware.fr")])
        #expect(await session.userKey() == nil)
        #expect(await !session.isLoggedIn())
    }

    @Test func deletedMarkerWinsOverAnotherMdUser() async {
        let session = makeSession(cookies: [
            StoredCookie(name: "md_user", value: "fakepseudo", domain: "forum.hardware.fr"),
            StoredCookie(name: "md_user", value: "deleted", domain: ".hardware.fr")
        ])
        #expect(await session.userKey() == nil)
    }

    @Test func serverLogoutIsSeen() async throws {
        let server = try LoopbackServer { _ in ServerReply(headers: ["Set-Cookie": "md_user=deleted; Path=/"]) }
        defer { server.stop() }
        let session = makeSession(cookies: [localCookie("md_user", "fakepseudo")])
        #expect(await session.isLoggedIn())
        _ = try await session.send(.get(server.baseURL.appending(path: "forum1.php")))
        #expect(await !session.isLoggedIn())
    }

    // MARK: - hash_check

    @Test func hashCheckIsUpdatedAndBlankValuesIgnored() async {
        let session = makeSession(hashCheck: "  ")
        #expect(await session.hashCheck == nil)
        await session.updateHashCheck("fakehash1")
        #expect(await session.hashCheck == "fakehash1")
        await session.updateHashCheck("")
        await session.updateHashCheck(nil)
        #expect(await session.hashCheck == "fakehash1")
        await session.updateHashCheck("fakehash2")
        #expect(await session.hashCheck == "fakehash2")
        #expect(await makeSession().hashCheck == nil)
    }

    @Test func hashCheckIsPerSession() async {
        let first = makeSession(hashCheck: "fakehashA")
        let second = makeSession(hashCheck: "fakehashB")
        await first.updateHashCheck("fakehashC")
        #expect(await second.hashCheck == "fakehashB")
    }

    // MARK: - Multi-quote

    private let topic = TopicID(category: .forum(13), topic: 42)
    private func token(_ numreponse: Int) -> QuoteSelectionToken {
        QuoteSelectionToken(forum: "hardwarefr", topic: topic, numreponse: numreponse)
    }

    @Test func toggleWritesTheSiteCookieAndDeletesItWhenEmpty() async throws {
        let session = makeSession()
        let now = Date()
        #expect(await session.toggleQuote(token(12), now: now))
        #expect(await session.toggleQuote(token(1), now: now))
        let cookie = try #require(await session.cookies(now: now).first)
        #expect(cookie.name == "quoteshardwarefr-13-42")
        #expect(cookie.value == "|12|1")
        #expect(cookie.domain == ".hardware.fr")
        #expect(cookie.path == "/")
        let lifetime = (cookie.expiresDate ?? now).timeIntervalSince(now)
        #expect(abs(lifetime - 3600) < 1)
        // The next quote or answer GET to the forum carries it.
        let forum = try #require(URL(string: "https://forum.hardware.fr/message.php"))
        #expect(await session.cookieNames(for: forum) == ["quoteshardwarefr-13-42"])

        #expect(await session.isQuoteSelected(token(1), now: now))
        #expect(await !session.isQuoteSelected(token(2), now: now))
        #expect(await !session.toggleQuote(token(12), now: now))
        #expect(await session.cookies(now: now).first?.value == "|1")
        #expect(await !session.toggleQuote(token(1), now: now))
        #expect(await session.cookies(now: now).isEmpty)
    }

    @Test func quoteSelectionMatchesExactly() async {
        let session = makeSession(cookies: [
            StoredCookie(name: "quoteshardwarefr-13-42", value: "|12", domain: ".hardware.fr", expiresDate: Date().addingTimeInterval(600))
        ])
        #expect(await !session.isQuoteSelected(token(1)))
        #expect(await session.isQuoteSelected(token(12)))
        #expect(await session.toggleQuote(token(1)))
        #expect(await session.multiQuote(for: token(1)).selectedNumbers == [12, 1])
    }

    @Test func expiredSelectionIsIgnoredAndRestartedOnToggle() async {
        let now = Date()
        let session = makeSession(cookies: [
            StoredCookie(name: "quoteshardwarefr-13-42", value: "|7", domain: ".hardware.fr", expiresDate: now.addingTimeInterval(600))
        ])
        let later = now.addingTimeInterval(7200)
        #expect(await !session.isQuoteSelected(token(7), now: later))
        #expect(await session.toggleQuote(token(8), now: later))
        #expect(await session.multiQuote(for: token(8), now: later).value == "|8")
    }

    @Test func selectionsOfDifferentTopicsAreSeparateAndClearable() async {
        let session = makeSession()
        let other = QuoteSelectionToken(forum: "hardwarefr", topic: TopicID(category: .forum(13), topic: 43), numreponse: 5)
        await session.toggleQuote(token(5))
        await session.toggleQuote(other)
        #expect(await session.cookies().count == 2)
        await session.clearQuotes(for: token(5))
        #expect(await session.cookies().map(\.name) == ["quoteshardwarefr-13-43"])
    }
}
