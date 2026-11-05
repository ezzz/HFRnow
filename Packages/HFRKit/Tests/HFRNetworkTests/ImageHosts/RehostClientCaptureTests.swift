import Foundation
import HFRModels
import Testing
@testable import HFRNetwork

/// The client on the host's real answers, `U01` (success) and `U02` (wrong key), captured 2026-11-02 (#394).
/// The files are read in place: a test bundle cannot read another one's resources (same as `HFRClientTests`).
struct RehostClientCaptureTests {
    private static let jpeg = Data([0xFF, 0xD8, 0xFF, 0xD9])
    private static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // ImageHosts
        .deletingLastPathComponent() // HFRNetworkTests
        .deletingLastPathComponent() // Tests
        .appendingPathComponent("HFRParsingTests/Fixtures/captures", isDirectory: true)

    private struct MetaStatus: Decodable { let status: Int }

    /// The body and HTTP status of capture `id`, as served.
    private static func capture(_ id: String, file: String) throws -> (status: Int, body: Data) {
        let meta = try JSONDecoder().decode(
            MetaStatus.self, from: Data(contentsOf: directory.appendingPathComponent(id + ".meta.json"))
        )
        return (meta.status, try Data(contentsOf: directory.appendingPathComponent(file)))
    }

    private func client(answering id: String, file: String) throws -> RehostClient {
        let (status, body) = try Self.capture(id, file: file)
        let url = try #require(URL(string: "https://img3.super-h.fr/api/1/upload/"))
        let transport = MockTransport(replies: [.success(HTTPResponse(statusCode: status, url: url, body: body))])
        let configuration = try RehostConfiguration(
            baseURL: #require(URL(string: "https://img3.super-h.fr")), apiKey: "FAKEKEY"
        )
        return RehostClient(configuration: configuration, transport: transport)
    }

    @Test func theCapturedSuccessGivesTheFullAndThumbnailURLsAndNoMedium() async throws {
        let image = try await client(answering: "U01", file: "U01-rehost-upload-success.json").upload(jpeg: Self.jpeg)
        #expect(image.fullURL.absoluteString == "https://img3.super-h.fr/images/2026/11/02/snapshot_1234567890.jpg")
        #expect(image.miniURL?.absoluteString == "https://img3.super-h.fr/images/2026/11/02/snapshot_1234567890.th.jpg")
        // `image.medium` is present with every field null: no medium rendition, not a failure.
        #expect(image.mediumURL == nil)
        #expect(image.width == 16)  // a JSON number in the capture
        #expect(image.height == 16)
        #expect(image.availableVariants == [.full, .mini])
    }

    @Test func theCapturedWrongKeyAnswerSurfacesTheHostMessage() async throws {
        let client = try client(answering: "U02", file: "U02-rehost-upload-wrong-key.json")
        await #expect(throws: RehostError.http(statusCode: 400, message: "Invalid API key.")) {
            try await client.upload(jpeg: Self.jpeg)
        }
    }
}
