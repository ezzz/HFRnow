import Foundation
import Testing
@testable import HFRNetwork

/// The default transport against a loopback server: no cookie leaves, nothing contacts the real host.
struct RehostClientLoopbackTests {
    @Test func uploadsCookielesslyThroughAnonymousTransport() async throws {
        let json = #"{"status_code":200,"image":{"url":"http://127.0.0.1/images/a.jpg"}}"#
        let server = try LoopbackServer { _ in ServerReply(headers: ["Set-Cookie": "sid=server; Path=/"], body: Data(json.utf8)) }
        defer { server.stop() }
        let configuration = try RehostConfiguration(baseURL: server.baseURL, apiKey: "FAKEKEY")
        let proxyless = URLSessionConfiguration.ephemeral
        proxyless.connectionProxyDictionary = [:]
        let client = RehostClient(configuration: configuration, transport: AnonymousTransport(configuration: proxyless))
        let jpeg = Data((0..<5000).map { UInt8($0 % 251) })

        let image = try await client.upload(jpeg: jpeg)
        _ = try await client.upload(jpeg: jpeg)
        #expect(image.fullURL.absoluteString == "http://127.0.0.1/images/a.jpg")

        let seen = try #require(server.requests.first)
        #expect(seen.method == "POST")
        #expect(seen.path == "/api/1/upload/?key=FAKEKEY")
        #expect(seen.headers["cookie"] == nil)
        #expect(server.requests.count == 2)
        #expect(server.requests.allSatisfy { $0.headers["cookie"] == nil }, "the host's cookie came back on the second upload")
        let contentType = try #require(seen.headers["content-type"])
        #expect(contentType.hasPrefix("multipart/form-data; boundary="))
        let boundary = String(contentType.dropFirst("multipart/form-data; boundary=".count))
        #expect(seen.body.starts(with: Data("--\(boundary)\r\n".utf8)))
        #expect(seen.body.range(of: jpeg) != nil, "the JPEG bytes arrive unchanged")
        let text = String(bytes: seen.body.prefix(400), encoding: .utf8) ?? ""
        #expect(text.contains("name=\"source\"; filename=\"snapshot_"))
    }

    @Test func aRedirectingHostIsNotFollowed() async throws {
        let target = try LoopbackServer { _ in ServerReply(body: Data(#"{"status_code":200}"#.utf8)) }
        defer { target.stop() }
        let redirect = target.baseURL.absoluteString
        let server = try LoopbackServer { _ in ServerReply(status: 307, headers: ["Location": redirect + "/elsewhere"]) }
        defer { server.stop() }
        let proxyless = URLSessionConfiguration.ephemeral
        proxyless.connectionProxyDictionary = [:]
        let client = try RehostClient(
            configuration: RehostConfiguration(baseURL: server.baseURL, apiKey: "FAKEKEY"),
            transport: AnonymousTransport(configuration: proxyless)
        )
        await #expect(throws: RehostError.http(statusCode: 307, message: nil)) { try await client.upload(jpeg: Data([1])) }
        #expect(target.requests.isEmpty, "the key and the image were replayed to the redirect target")
    }
}
