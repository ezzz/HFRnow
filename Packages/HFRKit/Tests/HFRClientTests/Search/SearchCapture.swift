import Foundation
import HFRNetwork

/// The search captures (`R50a`-`R50c`, `R52a`, `R52b`) and their legacy oracles, read in place.
enum SearchCapture {
    /// The legacy oracle output of capture `id` for lot `lot` (`LOT-002`, `LOT-005`), as raw JSON.
    static func oracle(_ lot: String, _ id: String) throws -> [String: Any] {
        let url = Capture.directory.deletingLastPathComponent().appendingPathComponent("\(lot)/\(id).oracle.json")
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
        guard let json = object as? [String: Any], let result = json["result"] as? [String: Any] else {
            throw Capture.Missing(name: "\(lot)/\(id) result")
        }
        return result
    }

    /// The page `file` served at the capture's own final URL, as HFR served it.
    static func answer(_ file: String, id: String) throws -> HTTPResponse {
        let meta = try Capture.meta(id)
        guard let url = URL(string: meta.finalURL ?? meta.url) else { throw Capture.Missing(name: "\(id) URL") }
        return try Capture.response(file, url: url, status: meta.status)
    }

    /// The request body a capture sent, as text.
    static func body(of request: HTTPRequest) -> String? {
        request.body.flatMap { String(bytes: $0, encoding: .utf8) }
    }
}
