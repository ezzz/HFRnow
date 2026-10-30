import Foundation
import HFRModels
import HFRNetwork
import HFRParsing
import Testing

/// #103: page N of a topic list is requested as `forum1.php?…&page=N`, which HFR redirects to `liste_sujet-N.htm`, and never
/// as `liste_sujet-1.htm?page=N`. Legacy built that last shape (`TopicPageURLRouting.replacingPage`, `Common.swift:2750-2759`
/// on `master`: no `page=` and no `_N.htm` in the path, so it appended `?page=N`) and showed page 1 under a "page 11" header.
/// Everything here is read from the captures `R04`, `R05a` and `R05b` (anonymous; the logged-in form of page N ≥ 2 is a
/// pending capture, HFR-PROTOCOL §7b B2).
@Suite("Topic list page N (#103)")
struct TopicListPageRequestTests {
    /// The parts of a capture's meta this suite reads.
    struct Meta: Decodable {
        struct Hop: Decodable {
            let status: Int
            let location: String
        }

        let url: String
        let finalURL: String
        let redirects: [Hop]

        enum CodingKeys: String, CodingKey {
            case url
            case finalURL = "final_url"
            case redirects
        }
    }

    static let cases = [
        ("R04", "R04-list-cat13-p1-anon", 1),
        ("R05a", "R05a-list-cat13-p12-anon", 12),
        ("R05b", "R05b-list-cat13-p500-anon", 500)
    ]

    private func meta(_ id: String) throws -> Meta {
        let url = Capture.directory.appendingPathComponent(id + ".meta.json")
        return try JSONDecoder().decode(Meta.self, from: Data(contentsOf: url))
    }

    @Test("The endpoint asks for page N exactly as the capture did, and HFR answered page N", arguments: cases)
    func endpointRequestsTheCapturedPage(id: String, file: String, page: Int) throws {
        let meta = try meta(id)
        let request = try HFREndpoint.topicList(category: .forum(13), page: page)
        #expect(request.url.absoluteString == meta.url)
        #expect(HFRURL.queryValue(named: "page", in: request.url.absoluteString) == String(page))
        #expect(!request.url.path().contains("liste_sujet"))
        // HFR's own answer: one 301 to the canonical list path of that page, which shows page N as current.
        #expect(meta.redirects.map(\.status) == [301])
        #expect(meta.redirects.map(\.location) == ["/hfr/Discussions/liste_sujet-\(page).htm"])
        #expect(meta.finalURL == "https://forum.hardware.fr/hfr/Discussions/liste_sujet-\(page).htm")
        let listPage = try TopicListParser.parse(Capture.page(file), pageURL: meta.finalURL)
        #expect(listPage.navigation.current == page)
    }

    @Test("The router reads page N from both shapes HFR used for that page", arguments: cases)
    func routerKeepsThePage(id: String, file: String, page: Int) throws {
        let meta = try meta(id)
        let expected = HFRLinkRoute.topicList(HFRTopicListLink(category: .forum(13), subcategory: nil, page: page, filter: .all))
        for link in [meta.url, meta.finalURL] {
            let url = try #require(URL(string: link))
            #expect(HFRLinkRoute.route(for: url) == expected, "\(link)")
        }
    }

    @Test("Every pager link of the captured pages routes to the page it names", arguments: cases)
    func pagerLinksRouteToTheirPage(id: String, file: String, page: Int) throws {
        let meta = try meta(id)
        let navigation = try TopicListParser.parse(Capture.page(file), pageURL: meta.finalURL).navigation
        let links = [
            (navigation.firstPath, navigation.first), (navigation.lastPath, navigation.last),
            (navigation.nextPath, navigation.current + 1), (navigation.previousPath, navigation.current - 1)
        ]
        var checked = 0
        for (path, target) in links {
            guard let path else { continue }
            let url = try #require(URL(string: "https://forum.hardware.fr" + path))
            guard case .topicList(let list) = HFRLinkRoute.route(for: url) else {
                Issue.record("\(path) is not a topic list")
                continue
            }
            #expect(list.page == target, "\(path)")
            #expect(!path.contains("?page="), "\(path)")
            checked += 1
        }
        #expect(checked >= 2)
    }
}
