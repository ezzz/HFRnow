import Foundation
import HFRModels
import HFRNetwork
import HFRParsing

/// The REST API's resource names (redface2 E1, LOT-057): the `uri` that `rest_api.php` takes, and the `/api/…` hrefs of
/// its answers, which HFR serves on a path that answers 404 (E1) and are rewritten to `rest_api.php?uri=…`.
enum RESTHref {
    /// Where an href or a built uri points: the resource and the paging the href carries.
    struct Target: Sendable, Equatable {
        /// Resource path, e.g. `forums/hardwarefr/categories/13/`.
        let uri: String
        let page: Int?
        let resultsPerPage: Int?
    }

    /// The forum's categories (`R57a`).
    static let categoriesURI = "forums/hardwarefr/categories/"

    /// One category (the `href` of an `R57a` row, a topic's `links.category`).
    static func categoryURI(_ category: Int) -> String {
        "\(categoriesURI)\(category)/"
    }

    /// The last topics of a category (`R57b`).
    static func lastTopicsURI(category: Int) -> String {
        "\(categoryURI(category))topics/last/"
    }

    /// One topic (`R57c`, the `href` of an `R57b` row).
    static func topicURI(category: Int, topic: Int) -> String {
        "\(categoryURI(category))topics/\(topic)/"
    }

    /// The target an href of an answer names, checked: `https://forum.hardware.fr/api/<uri>`, with no port, user or
    /// fragment, a uri of letters, digits, `_`, `-` and single `/` separators, and no query but `page` and
    /// `results_per_page` (positive numbers). A `posts` resource is refused: HFR answers it 500 (E1).
    static func target(of href: String) throws(ParsingError) -> Target {
        guard
            let url = URL(string: href),
            PostingFlow.isForumPage(url),
            url.port == nil,
            url.fragment == nil,
            let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
            components.percentEncodedPath.hasPrefix(apiPrefix)
        else { throw .invalidValue(field: "REST href") }
        let uri = String(components.percentEncodedPath.dropFirst(apiPrefix.count))
        guard isResourcePath(uri) else { throw .invalidValue(field: "REST href") }
        var page: Int?
        var resultsPerPage: Int?
        for item in components.queryItems ?? [] {
            guard let value = item.value.flatMap(Int.init), value >= 1 else { throw .invalidValue(field: "REST href query") }
            switch item.name {
            case "page" where page == nil: page = value
            case "results_per_page" where resultsPerPage == nil: resultsPerPage = value
            default: throw .invalidValue(field: "REST href query")
            }
        }
        return Target(uri: uri, page: page, resultsPerPage: resultsPerPage)
    }

    /// The GET of `target` through `rest_api.php`, redirects not followed: HFR answers in place (`R57a`-`R57c`).
    static func request(for target: Target) throws(NetworkError) -> HTTPRequest {
        guard isResourcePath(target.uri) else { throw .invalidRequest(reason: "not a REST resource") }
        var request: HTTPRequest
        do {
            request = try HFREndpoint.rest(uri: target.uri, page: target.page, resultsPerPage: target.resultsPerPage)
        } catch let error as NetworkError {
            throw error
        } catch {
            throw .invalidRequest(reason: "REST request could not be built")
        }
        request.redirectPolicy = .doNotFollow
        return request
    }

    /// Whether a topic's `href` names `topic` of `category`: `…/categories/<cat>/topics/<post>/` (`R57c`), or
    /// `…/categories/<cat>/subcategories/<sub>/topics/<post>/`, the shape of most `R57b` rows.
    static func names(topic: Int, category: Int, href: String) throws(ParsingError) -> Bool {
        let target = try target(of: href)
        guard target.page == nil, target.resultsPerPage == nil else { return false }
        if target.uri == topicURI(category: category, topic: topic) { return true }
        let prefix = "\(categoryURI(category))subcategories/"
        let suffix = "/topics/\(topic)/"
        guard target.uri.hasPrefix(prefix), target.uri.hasSuffix(suffix) else { return false }
        let subcategory = target.uri.dropFirst(prefix.count).dropLast(suffix.count)
        return Int(subcategory).map { $0 >= 1 && String($0) == subcategory } ?? false
    }

    /// The category a `links.category` href names (`…/categories/13/`).
    static func category(of href: String) throws(ParsingError) -> Int {
        let target = try target(of: href)
        let digits = target.uri.dropFirst(categoriesURI.count).dropLast()
        guard
            target.page == nil, target.resultsPerPage == nil, target.uri.hasPrefix(categoriesURI),
            let category = Int(digits), category >= 1, target.uri == categoryURI(category)
        else { throw .invalidValue(field: "links.category.href") }
        return category
    }

    // MARK: - Implementation

    private static let apiPrefix = "/api/"

    /// A uri this client may request: non-empty segments of `[A-Za-z0-9_-]`, ending with `/`, none of them `posts`.
    private static func isResourcePath(_ uri: String) -> Bool {
        guard uri.hasSuffix("/") else { return false }
        let segments = uri.dropLast().split(separator: "/", omittingEmptySubsequences: false)
        return !segments.isEmpty && segments.allSatisfy { segment in
            !segment.isEmpty && segment != "posts"
                && segment.unicodeScalars.allSatisfy { $0.isASCII && (CharacterSet.alphanumerics.contains($0) || $0 == "_" || $0 == "-") }
        }
    }
}
