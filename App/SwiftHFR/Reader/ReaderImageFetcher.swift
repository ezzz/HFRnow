import Foundation
import HFRNetwork

/// Downloads the images of the reader through the cookie-less client (LOT-045 `AnonymousTransport`), never the account
/// session: no forum cookie leaves the app with an image request and no `Referer` either, except the host table's own rule for the
/// image viewer (LOT-109, `reho.st`) (LOT-071 rules R1, R3).
///
/// Redirects are followed one hop at a time so the policy applies to every hop (LOT-071 edge cases): a public host that
/// redirects to a private address, or a forum image that redirects to a third party not allowed yet, stops there.
struct ReaderImageFetcher: Sendable {
    /// Why an image was not delivered.
    enum Failure: Error, Equatable {
        /// The policy refuses the URL or one of its redirect hops.
        case refused
        /// Not an image, too large, too many redirects, or a transport failure.
        case unavailable
    }

    /// Largest image accepted, in bytes; bounds the memory a hostile page can make the app hold per image.
    static let maximumBytes = 15 * 1024 * 1024
    /// Redirect hops followed before giving up.
    static let maximumRedirects = 5

    let transport: any HTTPTransport

    /// Creates a fetcher on `transport`, the cookie-less one by default.
    init(transport: any HTTPTransport = AnonymousTransport()) {
        self.transport = transport
    }

    /// The image at `url` and its MIME type. `allowsThirdParty` says whether a third-party host may be contacted (the
    /// user tapped, or the setting loads them by themselves); forum images are always allowed, blocked ones never.
    ///
    /// `hostTable` is set by the image viewer only (LOT-109): the request then carries the host's `Referer` rule (`reho.st`
    /// wants the forum's, legacy `PhotoViewerNetworkRequestFactory`), looked up again at every hop so it never travels to
    /// the next host. The page's own images (nil) carry none (LOT-071 R3).
    func image(
        at url: URL, allowsThirdParty: Bool, hostTable: ImageHostTable? = nil
    ) async throws(Failure) -> (data: Data, mimeType: String) {
        var next = url
        for _ in 0...Self.maximumRedirects {
            switch ImagePolicy.classify(next) {
            case .blocked: throw .refused
            case .thirdParty where !allowsThirdParty: throw .refused
            case .forum, .thirdParty: break
            }
            var request: HTTPRequest
            if let hostTable {
                do throws(NetworkError) { request = try hostTable.request(for: Self.upgraded(next)) } catch { throw .unavailable }
            } else {
                request = HTTPRequest.get(Self.upgraded(next), timeout: RequestTimeout.standard, redirectPolicy: .doNotFollow)
            }
            // The transport stops reading past the cap (or on a larger Content-Length); the check below covers any transport.
            request.maximumBodyBytes = Self.maximumBytes
            let response: HTTPResponse
            do throws(NetworkError) {
                response = try await transport.perform(request)
            } catch {
                throw .unavailable
            }
            if response.isRedirect {
                guard let location = response.redirectLocation else { throw .unavailable }
                next = location
                continue
            }
            guard (200..<300).contains(response.statusCode), response.body.count <= Self.maximumBytes,
                  let mimeType = Self.imageMIMEType(response.headers["Content-Type"]) else { throw .unavailable }
            return (response.body, mimeType)
        }
        throw .unavailable
    }

    /// `http` is requested over `https`: App Transport Security refuses clear-text loads and the app adds no exception
    /// (LOT-071 D-071-1 point 4). An `http`-only host fails and the page shows the image as a link.
    static func upgraded(_ url: URL) -> URL {
        guard url.scheme?.lowercased() == "http", var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            return url
        }
        components.scheme = "https"
        if components.port == 80 { components.port = nil }
        return components.url ?? url
    }

    /// The `image/*` type of a `Content-Type` header, lowercased, parameters dropped; nil for anything else.
    static func imageMIMEType(_ contentType: String?) -> String? {
        guard let type = contentType?.split(separator: ";").first?.trimmingCharacters(in: .whitespaces).lowercased(),
              type.hasPrefix("image/"), type.count > "image/".count else { return nil }
        return type
    }
}
