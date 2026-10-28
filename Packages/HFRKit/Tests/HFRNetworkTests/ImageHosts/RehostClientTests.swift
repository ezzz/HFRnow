import Foundation
import HFRModels
import Testing
@testable import HFRNetwork

/// The client against a scripted transport.
/// Payload shapes are those legacy reads (`ReplyService.swift:2002-2093` @ 2440d79).
struct RehostClientTests {
    private static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
    private static let uploadedAt = Date(timeIntervalSince1970: 1_700_000_000)

    private let configuration: RehostConfiguration
    private let endpoint: URL

    init() throws {
        endpoint = try #require(URL(string: "https://img.example/api/1/upload/"))
        configuration = try RehostConfiguration(baseURL: #require(URL(string: "https://img.example")), apiKey: "FAKEKEY")
    }

    private func client(_ transport: MockTransport) -> RehostClient {
        RehostClient(
            configuration: configuration, transport: transport, now: { Self.uploadedAt },
            makeFilename: { "snapshot_1.jpg" }, makeBoundary: { "Boundary-TEST" }
        )
    }

    private func reply(_ status: Int, _ json: String) -> Result<HTTPResponse, NetworkError> {
        .success(HTTPResponse(statusCode: status, url: endpoint, body: Data(json.utf8)))
    }

    private func reply(_ json: String) -> Result<HTTPResponse, NetworkError> { reply(200, json) }

    private static let success = """
    {"status_code":200,"success":{"message":"image uploaded","code":200},"image":{"url":"https://img.example/images/a.jpg",\
    "width":"640","height":480,"medium":{"url":"https://img.example/images/a.md.jpg"},\
    "thumb":{"url":"https://img.example/images/a.th.jpg"}}}
    """

    @Test func uploadsAndReturnsTheRenditions() async throws {
        let transport = MockTransport(replies: [reply(Self.success)])
        let image = try await client(transport).upload(jpeg: Self.jpeg)
        #expect(image.fullURL.absoluteString == "https://img.example/images/a.jpg")
        #expect(image.mediumURL?.absoluteString == "https://img.example/images/a.md.jpg")
        #expect(image.miniURL?.absoluteString == "https://img.example/images/a.th.jpg")
        #expect(image.width == 640)  // a string in the payload, as legacy accepted
        #expect(image.height == 480)
        #expect(image.uploadedAt == Self.uploadedAt)

        let request = try #require(await transport.requests.first)
        #expect(request.method == .post)
        #expect(request.url.absoluteString == "https://img.example/api/1/upload/?key=FAKEKEY")
        #expect(request.headers["Content-Type"] == "multipart/form-data; boundary=Boundary-TEST")
        #expect(request.headers["Cookie"] == nil)
        #expect(request.timeout == 60)
        #expect(request.redirectPolicy == .doNotFollow)
        let expected = MultipartBody(boundary: "Boundary-TEST", parts: [
            .text(name: "imageCaption", value: "Some Caption"),
            .file(name: "source", filename: "snapshot_1.jpg", contentType: "image/jpeg", data: Self.jpeg)
        ])
        #expect(request.body == expected.data)
    }

    @Test func aPayloadWithoutRenditionsStillSucceeds() async throws {
        let json = #"{"status_code":200,"image":{"url":"https://img.example/images/a.jpg"}}"#
        let image = try await client(MockTransport(replies: [reply(json)])).upload(jpeg: Self.jpeg)
        #expect(image.mediumURL == nil && image.miniURL == nil && image.width == nil)
        #expect(image.availableVariants == [.full])
    }

    @Test func unusableRenditionURLsAreDroppedNotTrusted() async throws {
        let json = """
        {"status_code":200,"image":{"url":"https://img.example/a.jpg","medium":{"url":"javascript:alert(1)"},"thumb":{"url":"/rel.jpg"}}}
        """
        let image = try await client(MockTransport(replies: [reply(json)])).upload(jpeg: Self.jpeg)
        #expect(image.mediumURL == nil && image.miniURL == nil)
    }

    @Test func httpErrorCarriesTheHostMessage() async throws {
        let json = #"{"status_code":400,"error":{"message":"Invalid API key.","code":100},"status_txt":"Bad Request"}"#
        await expectFailure(.http(statusCode: 400, message: "Invalid API key."), replies: [reply(400, json)])
        await expectFailure(.http(statusCode: 500, message: nil), replies: [reply(500, "<html>oops</html>")])
    }

    @Test func aTransportErrorNeverCarriesTheKeyOrFreeText() async throws {
        let withKey = try #require(URL(string: "https://img.example/api/1/upload/?key=FAKEKEY"))
        let sanitizedURL = try #require(URL(string: "https://img.example/api/1/upload/"))
        let cases: [(NetworkError, NetworkError)] = [
            (.httpStatus(code: 500, url: withKey), .httpStatus(code: 500, url: sanitizedURL)),
            (.invalidRequest(reason: "bad url ?key=FAKEKEY"), .invalidRequest(reason: "upload request refused"))
        ]
        for (raised, expected) in cases {
            await expectFailure(.network(expected), replies: [.failure(raised)])
        }
    }

    @Test func aMalformedStatusCodeIsNotConfirmation() async throws {
        let image = #""image":{"url":"https://img.example/a.jpg"}"#
        for status in [#""error""#, "null", "[]", "{}"] {
            await expectFailure(.invalidResponse, replies: [reply(200, "{\"status_code\":\(status),\(image)}")])
        }
        _ = try await client(MockTransport(replies: [reply(200, "{\"status_code\":\"200\",\(image)}")])).upload(jpeg: Self.jpeg)
    }

    @Test func aRedirectIsAFailureNotAFollowedUpload() async throws {
        await expectFailure(.http(statusCode: 302, message: nil), replies: [reply(302, "")])
    }

    @Test func aPayloadStatusOtherThan200IsRejected() async throws {
        let json = #"{"status_code":403,"error":{"message":"Not allowed"}}"#
        await expectFailure(.rejected(statusCode: 403, message: "Not allowed"), replies: [reply(200, json)])
    }

    /// Success is never reported without the host's confirmation.
    @Test func neverReportsSuccessWithoutAConfirmedImage() async throws {
        await expectFailure(.invalidResponse, replies: [reply(200, "not json")])
        await expectFailure(.invalidResponse, replies: [reply(200, "[]")])
        await expectFailure(.invalidResponse, replies: [reply(200, "")])
        await expectFailure(.missingImageURL, replies: [reply(200, #"{"status_code":200}"#)])
        await expectFailure(.missingImageURL, replies: [reply(200, #"{"status_code":200,"image":{"url":""}}"#)])
        await expectFailure(.missingImageURL, replies: [reply(200, #"{"status_code":200,"image":{"url":"ftp://x/a.jpg"}}"#)])
        // 2xx with no status_code falls back to the HTTP status, as legacy did.
        let bare = #"{"image":{"url":"https://img.example/a.jpg"}}"#
        _ = try await client(MockTransport(replies: [reply(200, bare)])).upload(jpeg: Self.jpeg)
    }

    @Test func transportFailuresAreWrappedAndNeverRetried() async throws {
        let transport = MockTransport(replies: [.failure(.timedOut), reply(Self.success)])
        let client = client(transport)
        await #expect(throws: RehostError.network(.timedOut)) { try await client.upload(jpeg: Self.jpeg) }
        #expect(await transport.requests.count == 1)
        let offline = self.client(MockTransport(replies: [.failure(.offline)]))
        await #expect(throws: RehostError.network(.offline)) { try await offline.upload(jpeg: Self.jpeg) }
    }

    @Test func nothingIsSentForEmptyData() async throws {
        let transport = MockTransport(replies: [])
        let client = client(transport)
        await #expect(throws: RehostError.emptyImage) { try await client.upload(jpeg: Data()) }
        #expect(await transport.requests.isEmpty)
    }

    @Test func aHostMessageEchoingTheKeyIsRedactedAndCapped() async throws {
        let json = #"{"status_code":400,"error":{"message":"bad key FAKEKEY"}}"#
        await expectFailure(.http(statusCode: 400, message: "bad key [key]"), replies: [reply(400, json)])
        let long = "{\"status_code\":400,\"error\":{\"message\":\"\(String(repeating: "x", count: 500))\"}}"
        let transport = MockTransport(replies: [reply(400, long)])
        do {
            _ = try await client(transport).upload(jpeg: Self.jpeg)
            Issue.record("expected a failure")
        } catch {
            guard case let .http(_, message?) = error else {
                Issue.record("unexpected \(error)")
                return
            }
            #expect(message.count == 200)
        }
    }

    private func expectFailure(_ expected: RehostError, replies: [Result<HTTPResponse, NetworkError>]) async {
        do {
            _ = try await client(MockTransport(replies: replies)).upload(jpeg: Self.jpeg)
            Issue.record("expected \(expected)")
        } catch {
            #expect(error == expected)
        }
    }
}
