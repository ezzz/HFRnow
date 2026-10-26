import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import HFRModels
import Testing
@testable import HFRNetwork

/// The anonymous transport (prefetch, images) must neither send nor keep cookies (HFR-PROTOCOL §7, E25).
struct AnonymousTransportTests {
    private func proxyless(_ configuration: URLSessionConfiguration) -> URLSessionConfiguration {
        configuration.connectionProxyDictionary = [:]
        return configuration
    }

    @Test func sendsNoCookieAndKeepsNoneFromTheServer() async throws {
        let server = try LoopbackServer { _ in ServerReply(headers: ["Set-Cookie": "sid=server; Path=/"]) }
        defer { server.stop() }
        let base = server.baseURL
        // Positive control: an account session sends both its imported cookie and the one the server set.
        let account = HFRSession(
            cookies: [StoredCookie(name: "md_user", value: "fakepseudo", domain: "127.0.0.1")],
            hashCheck: nil, now: Date(), configuration: proxyless(.ephemeral), hosts: .exactHost("127.0.0.1")
        )
        _ = try await account.send(.get(base.appending(path: "account/1")))
        _ = try await account.send(.get(base.appending(path: "account/2")))
        let accountHeader = server.requests.last { $0.path == "/account/2" }?.headers["cookie"]
        #expect(accountHeader?.contains("md_user=fakepseudo") == true)
        #expect(accountHeader?.contains("sid=server") == true)

        let anonymous = AnonymousTransport(configuration: proxyless(.ephemeral))
        _ = try await anonymous.send(.get(base.appending(path: "anon/1")))
        _ = try await anonymous.send(.get(base.appending(path: "anon/2")))
        _ = try await anonymous.send(.get(base.appending(path: "anon/3"), redirectPolicy: .doNotFollow))
        // A caller-supplied header is dropped too.
        _ = try await anonymous.send(.get(base.appending(path: "anon/4"), headers: ["cookie": "md_user=fakepseudo"]))
        // Whitespace around the name does not smuggle it through (Fable review of #27).
        _ = try await anonymous.send(.get(base.appending(path: "anon/5"), headers: [" Cookie": "md_user=fakepseudo"]))
        _ = try await anonymous.send(.get(base.appending(path: "anon/6"), headers: ["Cookie ": "md_user=fakepseudo"]))
        for path in ["/anon/1", "/anon/2", "/anon/3", "/anon/4", "/anon/5", "/anon/6"] {
            let seen = try #require(server.requests.last { $0.path == path })
            let names = seen.headers.keys.map { $0.trimmingCharacters(in: .whitespaces) }
            #expect(!names.contains("cookie"), "\(path) sent a cookie header")
            #expect(!seen.headers.values.contains { $0.contains("fakepseudo") }, "\(path) sent the value")
        }
    }

    @Test func configurationDisablesCookies() {
        let configuration = AnonymousTransport.cookieless(.ephemeral)
        #expect(configuration.httpCookieStorage == nil)
        #expect(!configuration.httpShouldSetCookies)
        #expect(configuration.httpCookieAcceptPolicy == .never)
        _ = AnonymousTransport()
    }
}
