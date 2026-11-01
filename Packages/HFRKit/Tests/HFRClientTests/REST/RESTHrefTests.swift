import Foundation
import HFRNetwork
import HFRParsing
import Testing
@testable import HFRClient

/// The `/api/…` hrefs of the REST answers and their rewrite to `rest_api.php?uri=…` (LOT-057, E1).
@Suite("REST hrefs (LOT-057)")
struct RESTHrefTests {
    @Test("Every href of R57a-R57c is rewritten on the forum origin, except the posts ones, which are refused")
    func capturedHrefs() throws {
        var rewritten = 0
        var posts = 0
        for file in [RESTCapture.categories, RESTCapture.lastTopics, RESTCapture.topic] {
            for href in try RESTCapture.hrefs(file) {
                if href.contains("/posts/") {
                    posts += 1
                    #expect(throws: ParsingError.invalidValue(field: "REST href")) { try RESTHref.target(of: href) }
                    continue
                }
                let request = try RESTHref.request(for: RESTHref.target(of: href))
                #expect(request.url.scheme == "https")
                #expect(request.url.host() == "forum.hardware.fr")
                #expect(request.url.path() == "/webservices/rest_api.php")
                #expect(request.redirectPolicy == .doNotFollow)
                let uri = String(href.dropFirst("https://forum.hardware.fr/api/".count).prefix { $0 != "?" })
                #expect(HFRURL.queryValue(named: "uri", in: request.url.absoluteString) == uri)
                rewritten += 1
            }
        }
        // Every non-null href of the three answers (81, 150 and 4) but the 31 `posts` ones.
        #expect(rewritten == 204)
        #expect(posts == 31)
    }

    @Test("The paging of a list href is kept: R57a's last_topics links")
    func pagingKept() throws {
        let href = "https://forum.hardware.fr/api/forums/hardwarefr/categories/1/topics/last/?page=1&results_per_page=25"
        let target = try RESTHref.target(of: href)
        #expect(target == RESTHref.Target(uri: "forums/hardwarefr/categories/1/topics/last/", page: 1, resultsPerPage: 25))
        let request = try RESTHref.request(for: target)
        let expected = "https://forum.hardware.fr/webservices/rest_api.php"
            + "?uri=forums/hardwarefr/categories/1/topics/last/&page=1&results_per_page=25"
        #expect(request.url.absoluteString == expected)
    }

    @Test("Off-origin or odd hrefs are refused", arguments: [
        "http://forum.hardware.fr/api/forums/hardwarefr/categories/",
        "https://forum.hardware.fr.example/api/forums/hardwarefr/categories/",
        "https://example.com/api/forums/hardwarefr/categories/",
        "https://forum.hardware.fr:8443/api/forums/hardwarefr/categories/",
        "https://user@forum.hardware.fr/api/forums/hardwarefr/categories/",
        "https://forum.hardware.fr/apix/forums/hardwarefr/categories/",
        "https://forum.hardware.fr/forums/hardwarefr/categories/",
        "https://forum.hardware.fr/api/forums/hardwarefr/../categories/",
        "https://forum.hardware.fr/api/forums//categories/",
        "https://forum.hardware.fr/api/forums/hardwarefr/categories",
        "https://forum.hardware.fr/api/forums/hardwarefr/categories/%2F/",
        "https://forum.hardware.fr/api/forums/hardwarefr/categories/#x",
        "https://forum.hardware.fr/api/forums/hardwarefr/categories/?page=0",
        "https://forum.hardware.fr/api/forums/hardwarefr/categories/?page=1&page=2",
        "https://forum.hardware.fr/api/forums/hardwarefr/categories/?uri=x",
        "https://forum.hardware.fr/api/forums/hardwarefr/categories/13/topics/28563/posts/",
        "/api/forums/hardwarefr/categories/",
        ""
    ])
    func refused(href: String) {
        #expect(throws: ParsingError.self) { try RESTHref.target(of: href) }
    }

    @Test("A topic href names its topic, with or without a sub-category; a category href names its category")
    func topicAndCategoryHrefs() throws {
        let base = "https://forum.hardware.fr/api/forums/hardwarefr/categories/13/"
        #expect(try RESTHref.names(topic: 28563, category: 13, href: base + "topics/28563/"))
        #expect(try RESTHref.names(topic: 28563, category: 13, href: base + "subcategories/433/topics/28563/"))
        #expect(try !RESTHref.names(topic: 28563, category: 14, href: base + "topics/28563/"))
        #expect(try !RESTHref.names(topic: 28564, category: 13, href: base + "subcategories/433/topics/28563/"))
        #expect(try !RESTHref.names(topic: 28563, category: 13, href: base + "subcategories/x/topics/28563/"))
        #expect(try !RESTHref.names(topic: 28563, category: 13, href: base + "subcategories/0/topics/28563/"))
        #expect(try !RESTHref.names(topic: 28563, category: 13, href: base + "subcategories/1/2/topics/28563/"))
        #expect(try RESTHref.category(of: base) == 13)
        #expect(throws: ParsingError.invalidValue(field: "links.category.href")) { try RESTHref.category(of: base + "topics/") }
        #expect(throws: ParsingError.invalidValue(field: "links.category.href")) {
            try RESTHref.category(of: "https://forum.hardware.fr/api/forums/hardwarefr/categories/013/")
        }
    }

    @Test("A posts uri is never requested, even built by hand")
    func postsNeverRequested() {
        #expect(throws: NetworkError.self) {
            try RESTHref.request(for: RESTHref.Target(uri: "forums/hardwarefr/categories/13/topics/28563/posts/"))
        }
    }
}
