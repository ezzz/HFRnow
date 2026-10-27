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

    /// Profile page 1, the page a session refresh reads (LOT-044).
    static let profilePage1 = URL(string: "https://forum.hardware.fr/user/editprofil.php?config=hfr.inc&page=1")
        ?? URL(fileURLWithPath: "/")

    /// The page served as HFR served it: UTF-8 HTML (every capture used here is `text/html; charset=utf-8`), status 200
    /// unless a test needs another one.
    static func response(_ file: String, url: URL = profilePage1, status: Int = 200) throws -> HTTPResponse {
        HTTPResponse(
            statusCode: status,
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
