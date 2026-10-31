import Foundation
import HFRNetwork

/// The REST captures `R57a`-`R57c` (LOT-057), read in place like every client capture.
enum RESTCapture {
    static let categories = "R57a-rest-categories"
    static let lastTopics = "R57b-rest-category-topics-last"
    static let topic = "R57c-rest-topic"

    /// The JSON bytes as HFR served them.
    static func data(_ file: String) throws -> Data {
        let url = Capture.directory.appendingPathComponent(file + ".json")
        guard let data = try? Data(contentsOf: url) else { throw Capture.Missing(name: file) }
        return data
    }

    /// The answer of capture `id` as the transport hands it over: status 200, `application/json`, the captured URL.
    static func response(_ file: String, id: String) throws -> HTTPResponse {
        let meta = try Capture.meta(id)
        guard let url = URL(string: meta.url) else { throw Capture.Missing(name: id) }
        return HTTPResponse(statusCode: meta.status, headers: ["Content-Type": "application/json"], url: url, body: try data(file))
    }

    /// The parsed JSON, to walk it independently of the client's decoder.
    static func object(_ file: String) throws -> [String: Any] {
        guard let object = try JSONSerialization.jsonObject(with: data(file)) as? [String: Any] else {
            throw Capture.Missing(name: file)
        }
        return object
    }

    /// Every `href` string anywhere in the capture, `null` ones left out.
    static func hrefs(_ file: String) throws -> [String] {
        var found: [String] = []
        var stack: [Any] = [try object(file)]
        while let value = stack.popLast() {
            if let dictionary = value as? [String: Any] {
                if let href = dictionary["href"] as? String { found.append(href) }
                stack.append(contentsOf: dictionary.values)
            } else if let array = value as? [Any] {
                stack.append(contentsOf: array)
            }
        }
        return found
    }
}
