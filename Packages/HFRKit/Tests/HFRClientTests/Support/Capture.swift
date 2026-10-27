import Foundation
import HFRNetwork

/// Reads the shared LOT-001 capture corpus from the source tree.
///
/// The corpus is a resource of `HFRParsingTests`; a test bundle cannot read another one's resources, and copying the
/// pages would fork them, so client tests read the files in place.
enum Capture {
    /// A capture file that could not be read.
    struct Missing: Error, CustomStringConvertible {
        let name: String
        var description: String { "Missing capture \(name)" }
    }

    static let directory = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Support
        .deletingLastPathComponent() // HFRClientTests
        .deletingLastPathComponent() // Tests
        .appendingPathComponent("HFRParsingTests/Fixtures/captures", isDirectory: true)

    /// Text of `<file>.html`, e.g. `page("W03-login-success")`.
    static func page(_ file: String) throws -> String {
        let url = directory.appendingPathComponent(file + ".html")
        guard let text = try? String(contentsOf: url, encoding: .utf8) else { throw Missing(name: file) }
        return text
    }

    /// The meta of capture `id`, e.g. `meta("W03")`.
    static func meta(_ id: String) throws -> CaptureMeta {
        let url = directory.appendingPathComponent(id + ".meta.json")
        guard let data = try? Data(contentsOf: url) else { throw Missing(name: id) }
        return try JSONDecoder().decode(CaptureMeta.self, from: data)
    }

    /// The page served as HFR served it: status 200, UTF-8 HTML (every capture used here is `text/html; charset=utf-8`).
    static func response(_ file: String, url: URL) throws -> HTTPResponse {
        HTTPResponse(
            statusCode: 200,
            headers: ["Content-Type": "text/html; charset=utf-8"],
            url: url,
            body: Data(try page(file).utf8)
        )
    }
}

/// The fields of a capture's `<id>.meta.json` the tests use.
struct CaptureMeta: Decodable {
    let status: Int
    let method: String
    let url: String
    let setCookieNames: [String]
    let requestFields: [String]?
    let requestBody: String?

    enum CodingKeys: String, CodingKey {
        case status, method, url
        case setCookieNames = "set_cookie_names"
        case requestFields = "request_fields"
        case requestBody = "request_body"
    }
}

extension Capture {
    /// `sideEffects.nbMP` the LOT-002 legacy oracle recorded for home capture `id` (`R01`-`R03`); nil when legacy found no entry.
    static func legacyUnreadCount(_ id: String) throws -> Int? {
        let url = directory.deletingLastPathComponent().appendingPathComponent("LOT-002/\(id).oracle.json")
        guard let data = try? Data(contentsOf: url) else { throw Missing(name: id + ".oracle") }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let effects = root["sideEffects"] as? [String: Any] else { throw Missing(name: id + ".oracle sideEffects") }
        // Only an explicit JSON null is "no entry"; a missing key or another type is a broken oracle.
        guard let value = effects["nbMP"] else { throw Missing(name: id + ".oracle nbMP") }
        if value is NSNull { return nil }
        guard let count = value as? Int else { throw Missing(name: id + ".oracle nbMP type") }
        return count
    }
}
