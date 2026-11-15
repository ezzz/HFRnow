import Foundation
import HFRModels
import HFRNetwork
import HFRParsing
import Testing
@testable import HFRClient

/// The REST answers captured after the first LOT-057 PRs: sub-categories (`R285a`-`R285c`, #285), paging and error answers
/// (`R57d`-`R57k`, #355), decoded and through the client.
@Suite("REST sub-categories, paging and errors (LOT-057)")
struct RESTCapturedSinceTests {
    static let home = URL(string: "https://forum.hardware.fr/") ?? URL(fileURLWithPath: "/")
    static let list13 = URL(string: "https://forum.hardware.fr/hfr/Discussions/liste_sujet-1.htm") ?? URL(fileURLWithPath: "/")
    static let api = "https://forum.hardware.fr/api/forums/hardwarefr/"

    private static func run<Value>(
        _ replies: [Result<HTTPResponse, NetworkError>],
        _ call: (RESTBrowsingClient) async throws(RESTBrowsingError) -> Value
    ) async -> (result: Result<Value, RESTBrowsingError>, requests: [HTTPRequest]) {
        let transport = MockTransport(replies: replies)
        let result: Result<Value, RESTBrowsingError>
        do {
            result = .success(try await call(RESTBrowsingClient(transport: transport)))
        } catch {
            result = .failure(error)
        }
        return (result, await transport.requests)
    }

    private static func edited(_ file: String, _ edit: (inout [String: Any]) -> Void) throws -> Data {
        var object = try RESTCapture.object(file)
        var resource = try #require(object["resource"] as? [String: Any])
        edit(&resource)
        object["resource"] = resource
        return try JSONSerialization.data(withJSONObject: object)
    }

    private static func editedFirstRow(_ file: String, _ edit: (inout [String: Any]) -> Void) throws -> Data {
        try edited(file) { resource in
            var rows = resource["resources"] as? [[String: Any]] ?? []
            edit(&rows[0])
            resource["resources"] = rows
        }
    }

    private static func rows(_ file: String) throws -> [[String: Any]] {
        try #require((RESTCapture.object(file)["resource"] as? [String: Any])?["resources"] as? [[String: Any]])
    }

    // MARK: - Sub-categories

    @Test("R285a-R285c: every sub-category in order, linked by its subcat number, as many as R57a's number_of_subcategories")
    func subcategories() throws {
        let categories = try Self.rows(RESTCapture.categories)
        for (file, category) in [(RESTCapture.subcategories1, 1), (RESTCapture.subcategories2, 2), (RESTCapture.subcategories10, 10)] {
            let links = try RESTDocument.subcategories(from: RESTCapture.data(file), category: category)
            let rows = try Self.rows(file)
            let expected = try rows.map { row in
                let id = try #require(row["id"] as? Int)
                let path = try #require(ForumCatalogue.topicListPath(categoryID: .forum(category), subcategory: id))
                return path
            }
            #expect(links.map(\.path) == expected)
            #expect(links.map(\.path).allSatisfy { $0.contains("&subcat=") && $0.contains("&cat=\(category)&") })
            let count = categories.first { $0["id"] as? Int == category }?["number_of_subcategories"] as? Int
            #expect(links.count == count)
        }
        let titles = try RESTDocument.subcategories(from: RESTCapture.data(RESTCapture.subcategories10), category: 10).map(\.title)
        // Entities decoded, the trailing space of « BI/Big Data » dropped.
        #expect(titles.contains("BI/Big Data"))
        let cooling = try RESTDocument.subcategories(from: RESTCapture.data(RESTCapture.subcategories2), category: 2).map(\.title)
        #expect(cooling.contains("Water & Xtreme Cooling"))
    }

    @Test("R285a: Hardware's 15 sub-categories are the home page's 15, same titles, same order (HFR-PROTOCOL §6b)")
    func hardwareMatchesHomePage() throws {
        let home = try ForumListParser.parse(Capture.page("R01-home-anon")).forums
        let hardware = try #require(home.first { $0.categoryID == .forum(1) })
        let links = try RESTDocument.subcategories(from: RESTCapture.data(RESTCapture.subcategories1), category: 1)
        #expect(links.map(\.title) == hardware.subforums.map(\.title))
    }

    @Test("A sub-category answer is checked at every level", arguments: [
        "list_type", "page", "href", "results_count", "empty", "row id", "row id twice", "row href", "row category", "row name"
    ])
    func subcategoriesChecked(edit: String) throws {
        let file = RESTCapture.subcategories1
        let data: Data
        let field: String
        switch edit {
        case "list_type": data = try Self.edited(file) { $0["list_type"] = "topic" }; field = "resource.list_type"
        case "page": data = try Self.edited(file) { $0["page"] = 2 }; field = "resource.page"
        case "href":
            data = try Self.edited(file) { $0["href"] = "https://forum.hardware.fr/api/forums/hardwarefr/categories/2/subcategories/" }
            field = "resource.href"
        case "results_count": data = try Self.edited(file) { $0["results_count"] = 14 }; field = "resource.results_count"
        case "empty": data = try Self.edited(file) { $0["resources"] = []; $0["results_count"] = 0 }; field = "resource.resources"
        case "row id": data = try Self.editedFirstRow(file) { $0["id"] = 0 }; field = "resource.resources.id"
        case "row id twice":
            data = try Self.edited(file) { resource in
                var rows = resource["resources"] as? [[String: Any]] ?? []
                rows[1] = rows[0]
                resource["resources"] = rows
            }
            field = "resource.resources.id"
        case "row href":
            data = try Self.editedFirstRow(file) { $0["href"] = "\(Self.api)categories/1/subcategories/109/" }
            field = "resource.resources.href"
        case "row category":
            data = try Self.editedFirstRow(file) { row in
                row["links"] = ["category": ["href": "https://forum.hardware.fr/api/forums/hardwarefr/categories/2/"]]
            }
            field = "resource.resources.links.category.href"
        default: data = try Self.editedFirstRow(file) { $0["name"] = "  " }; field = "resource.resources.name"
        }
        #expect(throws: ParsingError.invalidValue(field: field)) {
            try RESTDocument.subcategories(from: data, category: 1)
        }
    }

    @Test("A sub-category answer asked for another category is refused")
    func subcategoriesOfAnotherCategory() {
        #expect(throws: ParsingError.invalidValue(field: "resource.href")) {
            try RESTDocument.subcategories(from: RESTCapture.data(RESTCapture.subcategories1), category: 2)
        }
    }

    @Test("subcategories(in:): one GET of R285a's URL, no cookie; the home page's sub-forums when it fails")
    func subcategoriesClient() async throws {
        let r285a = try RESTCapture.response(RESTCapture.subcategories1, id: "R285a")
        let rest = await Self.run([.success(r285a)]) { client async throws(RESTBrowsingError) in
            try await client.subcategories(in: 1)
        }
        #expect(try rest.result.get().source == .rest)
        #expect(try rest.result.get().value.count == 15)
        let request = try #require(rest.requests.first)
        #expect(rest.requests.count == 1)
        #expect(request.url.absoluteString == (try Capture.meta("R285a")).url)
        #expect(request.redirectPolicy == .doNotFollow)
        #expect(request.headers["Cookie"] == nil)

        let error = NetworkError.httpStatus(code: 500, url: Self.home)
        let home = try Capture.response("R01-home-anon", url: Self.home)
        let fallback = await Self.run([.failure(error), .success(home)]) { client async throws(RESTBrowsingError) in
            try await client.subcategories(in: 10)
        }
        let forums = try ForumListParser.parse(Capture.page("R01-home-anon")).forums
        let programmation = try #require(forums.first { $0.categoryID == .forum(10) })
        #expect(try fallback.result.get() == RESTBrowsingResult(value: programmation.subforums, source: .html(.network(error))))
        #expect(fallback.requests.map(\.url.absoluteString) == [
            "https://forum.hardware.fr/webservices/rest_api.php?uri=forums/hardwarefr/categories/10/subcategories/",
            (try Capture.meta("R01")).url
        ])

        let absent = await Self.run([.failure(error), .success(home)]) { client async throws(RESTBrowsingError) in
            try await client.subcategories(in: 999)
        }
        guard case .failure(.page(.malformed)) = absent.result else {
            Issue.record("a category the home page lacks was read: \(absent.result)")
            return
        }
        let invalid = await Self.run([]) { client async throws(RESTBrowsingError) in try await client.subcategories(in: 0) }
        #expect(invalid.result.failure == .invalidTarget)
        #expect(invalid.requests.isEmpty)
    }

}

/// Paging and errors (#355).
extension RESTCapturedSinceTests {
    // MARK: - Paging

    @Test("R57d-R57f: the page asked, the sticky topics on page 1 only, an exact page count from results_count")
    func paging() throws {
        let page1 = try RESTDocument.lastTopics(from: RESTCapture.data(RESTCapture.lastTopicsPage1), category: 13, page: 1)
        let page2 = try RESTDocument.lastTopics(from: RESTCapture.data(RESTCapture.lastTopicsPage2), category: 13, page: 2)
        let wide = try RESTDocument.lastTopics(from: RESTCapture.data(RESTCapture.lastTopics50), category: 13, page: 1)
        // 93442 topics: 3738 pages of 25, 1869 of 50.
        #expect(page1.navigation == PageNavigation(current: 1, last: 3738, isExact: true))
        #expect(page2.navigation == PageNavigation(current: 2, last: 3738, isExact: true))
        #expect(wide.navigation == PageNavigation(current: 1, last: 1869, isExact: true))
        #expect(page1.topics.count == 30)
        #expect(page1.topics.prefix(5).allSatisfy { $0.isSticky })
        #expect(page2.topics.count == 25)
        #expect(page2.topics.allSatisfy { !$0.isSticky })
        #expect(wide.topics.count == 55)
        #expect(Set(page1.topics.map(\.topicID)).isDisjoint(with: page2.topics.map(\.topicID)))
        // The rows equal the JSON's, walked on its own.
        let ids = try Self.rows(RESTCapture.lastTopicsPage2).map { TopicID(category: .forum(13), topic: $0["id"] as? Int ?? 0) }
        #expect(page2.topics.map(\.topicID) == ids)
    }

    @Test("R57g: the page after the last is empty, not an error; the count says it is past the last")
    func pastTheLastPage() throws {
        let page = try RESTDocument.lastTopics(from: RESTCapture.data(RESTCapture.lastTopicsPastLast), category: 13, page: 3739)
        #expect(page.topics.isEmpty)
        #expect(page.navigation == PageNavigation(current: 3739, last: 3738, isExact: true))
    }

    @Test("A list page is checked against the page asked and its count", arguments: [
        "page", "href page", "href size", "href category", "results_count", "empty within the count", "rows past the count"
    ])
    func pageChecked(edit: String) throws {
        let data: Data
        var page = 2
        let field: String
        let file = RESTCapture.lastTopicsPage2
        switch edit {
        case "page": data = try RESTCapture.data(file); page = 1; field = "resource.page"
        case "href page":
            data = try Self.edited(file) { $0["href"] = "\(Self.api)categories/13/topics/last/?page=1&results_per_page=25" }
            field = "resource.href"
        case "href size":
            data = try Self.edited(file) { $0["href"] = "\(Self.api)categories/13/topics/last/?page=2&results_per_page=50" }
            field = "resource.href"
        case "href category":
            data = try Self.edited(file) { $0["href"] = "\(Self.api)categories/14/topics/last/?page=2&results_per_page=25" }
            field = "resource.href"
        case "results_count": data = try Self.edited(file) { $0["results_count"] = 0 }; field = "resource.results_count"
        case "empty within the count": data = try Self.edited(file) { $0["resources"] = [] }; field = "resource.resources"
        default: data = try Self.edited(file) { $0["results_count"] = 25 }; field = "resource.resources"
        }
        #expect(throws: ParsingError.invalidValue(field: field)) {
            try RESTDocument.lastTopics(from: data, category: 13, page: page)
        }
    }

    @Test("lastTopics(in:page:): page 2 is R57e's URL; a later page has no HTML fallback; a page below 1 sends nothing")
    func pagingClient() async throws {
        let r57e = try RESTCapture.response(RESTCapture.lastTopicsPage2, id: "R57e")
        let page2 = await Self.run([.success(r57e)]) { client async throws(RESTBrowsingError) in
            try await client.lastTopics(in: 13, page: 2)
        }
        #expect(try page2.result.get().source == .rest)
        #expect(try page2.result.get().value.topics.count == 25)
        #expect(page2.requests.map(\.url.absoluteString) == [(try Capture.meta("R57e")).url])
        #expect(page2.requests.first?.headers["Cookie"] == nil)

        let error = NetworkError.httpStatus(code: 500, url: Self.home)
        let failed = await Self.run([.failure(error)]) { client async throws(RESTBrowsingError) in
            try await client.lastTopics(in: 13, page: 2)
        }
        #expect(failed.result.failure == .network(error))
        #expect(failed.requests.count == 1)

        let notJSON = HTTPResponse(statusCode: 200, url: Self.home, body: Data("<html></html>".utf8))
        let malformed = await Self.run([.success(notJSON)]) { client async throws(RESTBrowsingError) in
            try await client.lastTopics(in: 13, page: 2)
        }
        #expect(malformed.result.failure == .response(.malformedDocument))

        let invalid = await Self.run([]) { client async throws(RESTBrowsingError) in try await client.lastTopics(in: 13, page: 0) }
        #expect(invalid.result.failure == .invalidTarget)
        #expect(invalid.requests.isEmpty)
    }

    // MARK: - Errors

    @Test("R57i, R57k: HFR's error answer is read from the body (200), its code kept; R57b and R57j are not errors")
    func errorAnswers() throws {
        #expect(RESTDocument.errorCode(in: try RESTCapture.data(RESTCapture.unknownCategory)) == 403)
        #expect(RESTDocument.errorCode(in: try RESTCapture.data(RESTCapture.unknownResource)) == 404)
        #expect(RESTDocument.errorCode(in: try RESTCapture.data(RESTCapture.lastTopics)) == nil)
        #expect(RESTDocument.errorCode(in: try RESTCapture.data(RESTCapture.unknownTopic)) == nil)
        #expect(RESTDocument.errorCode(in: Data("<html></html>".utf8)) == nil)
        // `error` false, or a resource beside it, is not the error answer.
        #expect(RESTDocument.errorCode(in: Data(#"{"resource":null,"error":false,"error_code":403}"#.utf8)) == nil)
        #expect(RESTDocument.errorCode(in: Data(#"{"resource":{},"error":true,"error_code":403}"#.utf8)) == nil)
    }

    @Test("An error answer falls back on page 1 with its code as the reason, and ends a call without fallback")
    func errorAnswersThroughTheClient() async throws {
        let r57i = try RESTCapture.response(RESTCapture.unknownCategory, id: "R57i")
        let list = try Capture.response("R04-list-cat13-p1-anon", url: Self.list13)
        let page1 = await Self.run([.success(r57i), .success(list)]) { client async throws(RESTBrowsingError) in
            try await client.lastTopics(in: 13)
        }
        #expect(try page1.result.get().source == .html(.refused(code: 403)))

        let page2 = await Self.run([.success(r57i)]) { client async throws(RESTBrowsingError) in
            try await client.lastTopics(in: 13, page: 2)
        }
        #expect(page2.result.failure == .refused(code: 403))

        let r57k = try RESTCapture.response(RESTCapture.unknownResource, id: "R57k")
        let topic = await Self.run([.success(r57k)]) { client async throws(RESTBrowsingError) in
            try await client.topic(TopicID(category: .forum(13), topic: 28563))
        }
        #expect(topic.result.failure == .refused(code: 404))
    }

    @Test("R57j: an unknown topic is HFR's placeholder, not an error answer: notFound; asked as another topic, refused")
    func unknownTopic() async throws {
        let id = TopicID(category: .forum(13), topic: 999_999_999)
        #expect(try RESTDocument.topic(from: RESTCapture.data(RESTCapture.unknownTopic), expected: id) == nil)
        #expect(throws: ParsingError.invalidValue(field: "resource.id")) {
            let other = TopicID(category: .forum(14), topic: 999_999_999)
            return try RESTDocument.topic(from: RESTCapture.data(RESTCapture.unknownTopic), expected: other)
        }
        let r57j = try RESTCapture.response(RESTCapture.unknownTopic, id: "R57j")
        let run = await Self.run([.success(r57j)]) { client async throws(RESTBrowsingError) in try await client.topic(id) }
        #expect(run.result.failure == .notFound)
        #expect(run.requests.map(\.url.absoluteString) == [(try Capture.meta("R57j")).url])
        // A real topic with an empty title stays a decoding failure: only the empty title with a null date is the placeholder.
        let titled = try Self.edited(RESTCapture.topic) { $0["title"] = "" }
        #expect(throws: ParsingError.invalidValue(field: "resource.title")) {
            try RESTDocument.topic(from: titled, expected: TopicID(category: .forum(13), topic: 28563))
        }
    }

    @Test("R57h: the /api/ href HFR answers 404 is requested through rest_api.php, as R57a was")
    func apiHrefRewritten() throws {
        let api = try Capture.meta("R57h").url
        let request = try RESTHref.request(for: RESTHref.target(of: api))
        #expect(request.url.absoluteString == (try Capture.meta("R57a")).url)
        // The 404 page itself is not JSON.
        let page = try Data(contentsOf: Capture.directory.appendingPathComponent("R57h-api-href-as-is-404.html"))
        #expect(throws: ParsingError.malformedDocument) { try RESTDocument.categories(from: page) }
    }
}

private extension Result {
    var failure: Failure? {
        if case .failure(let error) = self { return error }
        return nil
    }
}
