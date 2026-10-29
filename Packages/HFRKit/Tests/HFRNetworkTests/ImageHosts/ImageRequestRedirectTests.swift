import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import Testing
@testable import HFRNetwork

/// An image request leaves each hop to the caller (LOT-071 D-071-1: block rules on every hop, no `Referer` carried along).
struct ImageRequestRedirectTests {
    @Test func aRedirectToAPrivateAddressIsReturnedNotFollowed() async throws {
        let server = try LoopbackServer { _ in ServerReply(status: 302, headers: ["Location": "http://192.168.1.1/admin.png"]) }
        defer { server.stop() }
        let proxyless = URLSessionConfiguration.ephemeral
        proxyless.connectionProxyDictionary = [:]
        let transport = AnonymousTransport(configuration: proxyless)
        let request = try ImageHostTable(rules: [ImageHostRule(host: "127.0.0.1", referer: "https://forum.hardware.fr")])
            .request(for: server.baseURL.appending(path: "thumb/a.png"))

        let response = try await transport.perform(request)
        #expect(response.statusCode == 302)
        #expect(response.redirectLocation?.host == "192.168.1.1")
        #expect(server.requests.count == 1, "the redirect was followed")
        #expect(server.requests.first?.headers["referer"] == "https://forum.hardware.fr")
    }
}
