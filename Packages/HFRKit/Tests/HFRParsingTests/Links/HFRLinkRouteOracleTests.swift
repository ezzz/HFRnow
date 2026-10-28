import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// Differential tests (LESSONS 52): the link router against what the legacy parsers computed on the same captures.
///
/// Legacy never routed a link, so the router is checked on the part legacy did compute: the page of each link
/// (`ObjCTopicPageWorker.m:14-43`, via `maxTopicPage`, `pageNumber`, `currentPage`), the message of each permalink
/// (`postID`), and the category (`cat=` of the quote link beside each canonical permalink).
@Suite("Link router vs LOT-002 / LOT-003 oracles")
struct HFRLinkRouteOracleTests {
    /// Every oracle file of the two directories, decoded as untyped JSON: the shapes differ by `kind`.
    static func oracles(in subdirectory: String) throws -> [(name: String, json: [String: Any])] {
        let urls = Bundle.module.urls(forResourcesWithExtension: "json", subdirectory: subdirectory) ?? []
        return try urls.filter { $0.lastPathComponent.hasSuffix(".oracle.json") }.sorted { $0.path < $1.path }.compactMap { url in
            let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url))
            return (url.lastPathComponent, object as? [String: Any] ?? [:])
        }
    }

    /// Every dictionary nested anywhere in `value`.
    static func dictionaries(in value: Any) -> [[String: Any]] {
        if let dictionary = value as? [String: Any] {
            return [dictionary] + dictionary.values.flatMap { dictionaries(in: $0) }
        }
        if let array = value as? [Any] {
            return array.flatMap { dictionaries(in: $0) }
        }
        return []
    }

    static func url(_ link: String) throws -> URL {
        try #require(HFRURL.absolute(link), "\(link) is a forum link")
    }

    static func page(of route: HFRLinkRoute) -> Int? {
        switch route {
        case .topic(let link), .privateMessageThread(let link): link.page
        case .topicList(let link): link.page
        case .privateMessageList(let page): page
        // A search results route keeps the whole path, so its page is the `page=` of that path, 1 on the first results page.
        case .searchResults(let path): HFRURL.queryValue(named: "page", in: path).flatMap(Int.init) ?? 1
        default: nil
        }
    }

    /// Routes that must carry the page the legacy parser computed.
    static func expectPage(_ expected: Int, of link: String, _ label: String) throws {
        let route = HFRLinkRoute.route(for: try url(link))
        #expect(Self.page(of: route) == expected, "\(label): \(link) -> \(route)")
    }

    @Test("Page numbers of list links equal the legacy ones; topic links equal HFRURL, the port of the legacy regexes")
    func listOracles() throws {
        var checked = 0
        for (name, json) in try Self.oracles(in: "Fixtures/LOT-002") {
            for dictionary in Self.dictionaries(in: json["result"] ?? [:]) {
                if let link = dictionary["aURLOfLastPage"] as? String, let max = dictionary["maxTopicPage"] as? Int {
                    try Self.expectPage(max, of: link, "\(name) maxTopicPage")
                    checked += 1
                }
                if let link = dictionary["currentUrl"] as? String, let number = dictionary["pageNumber"] as? Int,
                   case .topicList = HFRLinkRoute.route(for: try Self.url(link)) {
                    try Self.expectPage(number, of: link, "\(name) pageNumber")
                    checked += 1
                }
                if let link = dictionary["lastPageUrl"] as? String, !link.isEmpty, let number = dictionary["lastPageNumber"] as? Int {
                    try Self.expectPage(number, of: link, "\(name) lastPageNumber")
                    checked += 1
                }
                if let link = dictionary["firstPageUrl"] as? String, !link.isEmpty, let number = dictionary["firstPageNumber"] as? Int {
                    try Self.expectPage(number, of: link, "\(name) firstPageNumber")
                    checked += 1
                }
                if let link = dictionary["nextPageUrl"] as? String, !link.isEmpty, let number = dictionary["pageNumber"] as? Int,
                   case .topicList = HFRLinkRoute.route(for: try Self.url(link)) {
                    try Self.expectPage(number + 1, of: link, "\(name) nextPageUrl")
                    checked += 1
                }
            }
        }
        #expect(checked > 400, "the oracles hold hundreds of page links; checked \(checked)")
    }

    @Test("Every topic link of the list oracles routes to the topic, page and message HFRURL reads from it")
    func topicLinksAgreeWithHFRURL() throws {
        var checked = 0
        for (name, json) in try Self.oracles(in: "Fixtures/LOT-002") {
            for dictionary in Self.dictionaries(in: json["result"] ?? [:]) {
                for key in ["aURL", "aURLOfFirstPage", "aURLOfLastPage", "aURLOfLastPost"] {
                    guard let link = dictionary[key] as? String, !link.isEmpty else { continue }
                    let route = HFRLinkRoute.route(for: try Self.url(link))
                    let topic: HFRTopicLink
                    switch route {
                    case .topic(let value), .privateMessageThread(let value): topic = value
                    case .topicList(let list):
                        // The home page oracles (R01-R03) hold forum and sub-forum list links in `aURL`.
                        let expected = link.firstMatch(of: /liste_sujet-([0-9]+)\.htm/).flatMap { Int($0.output.1) } ?? 1
                        #expect(list.page == expected, "\(name) \(key) list page: \(link)")
                        checked += 1
                        continue
                    default:
                        Issue.record("\(name) \(key): \(link) is a topic link, got \(route)")
                        continue
                    }
                    #expect(topic.id.topic == HFRURL.topicNumber(in: link), "\(name) \(key) topic")
                    #expect(topic.page == HFRURL.page(in: link), "\(name) \(key) page: \(link)")
                    #expect(topic.anchorPostNumber == HFRURL.anchorPostNumber(in: link), "\(name) \(key) anchor: \(link)")
                    if link.contains("cat=") {
                        #expect(topic.id.category == HFRURL.category(in: link), "\(name) \(key) category")
                    }
                    checked += 1
                }
            }
        }
        #expect(checked > 1000, "checked \(checked)")
    }

    @Test("Topic page oracles: current page, permalinks (page, message) and the category beside the quote link")
    func topicOracles() throws {
        var pages = 0
        var permalinks = 0
        for (name, json) in try Self.oracles(in: "Fixtures/LOT-003") {
            let result = json["result"] as? [String: Any] ?? [:]
            if let page = result["page"] as? [String: Any], let link = page["currentURL"] as? String,
               let current = page["currentPage"] as? Int {
                try Self.expectPage(current, of: link, "\(name) currentPage")
                pages += 1
            }
            for action in result["actions"] as? [[String: Any]] ?? [] {
                guard let permalink = action["permalinkURL"] as? String, let postID = action["postID"] as? String else { continue }
                let route = HFRLinkRoute.route(for: try Self.url(permalink))
                let topic: HFRTopicLink
                switch route {
                case .topic(let value), .privateMessageThread(let value): topic = value
                default:
                    Issue.record("\(name): permalink \(permalink) -> \(route)")
                    continue
                }
                #expect("t\(topic.anchorPostNumber ?? 0)" == postID, "\(name) permalink message")
                #expect(topic.page == HFRURL.page(in: permalink), "\(name) permalink page")
                // The slug-to-category table (ForumCatalogue) against the `cat` the same message's quote link carries.
                if let quote = action["quoteURL"] as? String, let category = HFRURL.category(in: quote) {
                    #expect(topic.id.category == category, "\(name) permalink category vs quote link")
                    #expect(topic.id.topic == HFRURL.topicNumber(in: quote), "\(name) permalink topic vs quote link")
                }
                permalinks += 1
            }
        }
        #expect(pages >= 15, "checked \(pages) pages")
        #expect(permalinks > 100, "checked \(permalinks) permalinks")
    }
}
