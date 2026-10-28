import Foundation
import HFRModels
/// Uploads an image to the Chevereto host and returns where it landed.
///
/// Replaces legacy `Img3ReplyImageUploadService` (`ReplyService.swift:1958` @ 2440d79).
///
/// The request carries no cookie: the default transport is `AnonymousTransport`, and an explicit `Cookie` header is
/// never set. Re-encoding to JPEG and downscaling (`RehostMaxDimension`) need UIKit and stay in the app, which passes
/// the JPEG bytes. A POST is never retried and a redirect is not followed: only the host's own confirmation counts as
/// success, so a lost answer is reported as an error and the user decides whether to upload again.
public struct RehostClient: Sendable {
    /// Total time limit of an upload, in seconds (legacy `ReplyService.swift:1992` @ 2440d79).
    public static let uploadTimeout: Double = 60
    /// Form field that carries a caption; legacy sent this constant with every upload (`ReplyService.swift:2050` @ 2440d79).
    static let captionValue = "Some Caption"

    private let configuration: RehostConfiguration
    private let transport: any HTTPTransport
    private let now: @Sendable () -> Date
    private let makeFilename: @Sendable () -> String
    private let makeBoundary: @Sendable () -> String

    /// Creates a client. The closures are injection points for tests; the defaults are the production behaviour.
    public init(
        configuration: RehostConfiguration,
        transport: any HTTPTransport = AnonymousTransport(),
        now: @escaping @Sendable () -> Date = { Date() },
        makeFilename: @escaping @Sendable () -> String = { "snapshot_\(Int.random(in: 1...Int.max)).jpg" },
        makeBoundary: @escaping @Sendable () -> String = { "Boundary-\(UUID().uuidString)" }
    ) {
        self.configuration = configuration
        self.transport = transport
        self.now = now
        self.makeFilename = makeFilename
        self.makeBoundary = makeBoundary
    }

    /// Uploads JPEG bytes and returns the hosted image with its renditions.
    public func upload(jpeg: Data) async throws(RehostError) -> RehostedImage {
        guard !jpeg.isEmpty else { throw .emptyImage }
        let body = MultipartBody(boundary: makeBoundary(), parts: [
            .text(name: "imageCaption", value: Self.captionValue),
            .file(name: "source", filename: makeFilename(), contentType: "image/jpeg", data: jpeg)
        ])
        let request = HTTPRequest(
            url: try configuration.uploadURL(), method: .post, headers: ["Content-Type": body.contentType],
            body: body.data, timeout: Self.uploadTimeout, redirectPolicy: .doNotFollow
        )
        let response: HTTPResponse
        do {
            response = try await transport.perform(request)
        } catch {
            throw .network(Self.sanitized(error))
        }
        return try interpret(response)
    }

    /// The upload URL carries the key in its query and a transport's `reason` is free text: neither may reach the caller.
    private static func sanitized(_ error: NetworkError) -> NetworkError {
        switch error {
        case let .httpStatus(code, url):
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            components?.query = nil
            components?.user = nil
            components?.password = nil
            return .httpStatus(code: code, url: components?.url ?? url.deletingLastPathComponent())
        case .invalidRequest:
            return .invalidRequest(reason: "upload request refused")
        default:
            return error
        }
    }

    private func interpret(_ response: HTTPResponse) throws(RehostError) -> RehostedImage {
        let payload = RehostResponse.decode(response.body)
        let message = payload?.message.map { String(configuration.redacting($0).prefix(200)) }
        guard (200...299).contains(response.statusCode) else {
            throw .http(statusCode: response.statusCode, message: message)
        }
        guard let payload else { throw .invalidResponse }
        let status = payload.statusCode ?? response.statusCode
        guard status == 200 else { throw .rejected(statusCode: status, message: message) }
        guard let image = payload.hostedImage(uploadedAt: now()) else { throw .missingImageURL }
        return image
    }
}
