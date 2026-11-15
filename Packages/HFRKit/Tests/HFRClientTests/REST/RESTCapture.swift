import Foundation
import HFRNetwork

/// The REST captures `R57a`-`R57k`, the sub-categories `R285a`-`R285c` and the flag buckets `R335a`-`R335e`, `R603f`, `R830t`
/// (LOT-057), read in place like every client capture.
enum RESTCapture {
    static let categories = "R57a-rest-categories"
    static let lastTopics = "R57b-rest-category-topics-last"
    static let topic = "R57c-rest-topic"
    /// Paging and errors, anonymous (#355): page 1 and 2 asked with `page`, page 1 at 50 per page, the page after the last,
    /// an unknown category (error 403), an unknown topic (placeholder), an unknown resource (error 404).
    static let lastTopicsPage1 = "R57d-rest-category-topics-last-page1"
    static let lastTopicsPage2 = "R57e-rest-category-topics-last-page2"
    static let lastTopics50 = "R57f-rest-category-topics-last-per-page50"
    static let lastTopicsPastLast = "R57g-rest-category-topics-last-past-last-page"
    static let unknownCategory = "R57i-rest-error-unknown-category"
    static let unknownTopic = "R57j-rest-unknown-topic"
    static let unknownResource = "R57k-rest-error-unknown-resource"
    /// The sub-categories of categories 1, 2 and 10, anonymous (#285).
    static let subcategories1 = "R285a-rest-subcategories-cat1"
    static let subcategories2 = "R285b-rest-subcategories-cat2"
    static let subcategories10 = "R285c-rest-subcategories-cat10"
    /// The logged-in flag buckets (#335): global `participated`, `read`, `favorites`, the global `participated` asked for a
    /// page 2 of 5, and the flat forms of one category (`R335e`, `R603f`).
    static let participated = "R335a-rest-bucket-participated"
    static let read = "R335b-rest-bucket-read"
    static let favorites = "R335c-rest-bucket-favorites"
    static let participatedPage2 = "R335d-rest-bucket-participated-page2-per-page5"
    static let participatedCategory = "R335e-rest-bucket-participated-category-page2-per-page5"
    static let readCategory = "R603f-rest-bucket-read-category"

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
