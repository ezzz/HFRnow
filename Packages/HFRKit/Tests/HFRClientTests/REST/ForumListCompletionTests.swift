import Foundation
import HFRModels
import HFRNetwork
import Testing
@testable import HFRClient
@testable import HFRParsing

/// LOT-168: every sub-forum HFR has, the home page first, the REST sub-categories (`R285a`-`R285c`) completing it; the
/// injection table checked against those captures.
@Suite("Forum list completeness (LOT-168)")
struct ForumListCompletionTests {
    /// The captured categories: `cat` id, REST capture and its meta id.
    static let captured: [Captured] = [
        Captured(category: 1, file: RESTCapture.subcategories1, id: "R285a"),
        Captured(category: 2, file: RESTCapture.subcategories2, id: "R285b"),
        Captured(category: 10, file: RESTCapture.subcategories10, id: "R285c")
    ]

    struct Captured {
        let category: Int
        let file: String
        let id: String
    }

    private static func link(_ title: String, _ path: String = "") -> ForumLink {
        ForumLink(title: title, path: path.isEmpty ? "/hfr/x/\(title)/liste_sujet-1.htm" : path)
    }

    private static func rest(_ file: String, category: Int) throws -> [ForumLink] {
        try RESTDocument.subcategories(from: RESTCapture.data(file), category: category)
    }

    private static func home() throws -> [ForumCategory] {
        try ForumListParser.parse(Capture.page("R01-home-anon")).forums
    }

    // MARK: - The completion

    @Test("Each captured category shows as many sub-forums as the REST list holds, the page's links and order kept")
    func completesEveryCapturedCategory() throws {
        let forums = try Self.home()
        for entry in Self.captured {
            let (category, file) = (entry.category, entry.file)
            let home = try #require(forums.first { $0.categoryID == .forum(category) }).subforums
            let rows = try Self.rest(file, category: category)
            let completed = ForumListCompletion.complete(home, with: rows)
            #expect(completed.count == rows.count)
            // The page's links keep their paths and their relative order.
            #expect(completed.filter { home.contains($0) } == home)
            // Every REST row is there, by title.
            #expect(Set(completed.map { ForumListCompletion.key($0.title) }) == Set(rows.map { ForumListCompletion.key($0.title) }))
        }
    }

    @Test("Programmation: 27 sub-forums where the page (injections included) lists 13; the 14 added ones are REST links")
    func programmation() throws {
        let home = try #require(try Self.home().first { $0.categoryID == .forum(10) }).subforums
        let rows = try Self.rest(RESTCapture.subcategories10, category: 10)
        let completed = ForumListCompletion.complete(home, with: rows)
        #expect(home.count == 13)
        #expect(completed.count == 27)
        let added = completed.filter { !home.contains($0) }
        #expect(added.count == 14)
        #expect(added.allSatisfy { $0.path.contains("&subcat=") })
        // REST order places the added ones: « Ada » first, « Algo » then « Android » follow the REST rows before them.
        #expect(completed.prefix(3).map(\.title) == ["Ada", "Algo", "Android"])
    }

    @Test("Hardware and Overclocking: the table's « Bench » is kept, « Divers » of Overclocking (its trigger is not listed) is added")
    func hardwareAndOverclocking() throws {
        let forums = try Self.home()
        let hardware = try #require(forums.first { $0.categoryID == .forum(1) }).subforums
        let rows1 = try Self.rest(RESTCapture.subcategories1, category: 1)
        #expect(ForumListCompletion.complete(hardware, with: rows1) == hardware)
        let cooling = try #require(forums.first { $0.categoryID == .forum(2) }).subforums
        let completed = ForumListCompletion.complete(cooling, with: try Self.rest(RESTCapture.subcategories2, category: 2))
        #expect(cooling.count == 6)
        #expect(completed.map(\.title) == cooling.map(\.title) + ["Divers"])
    }

    @Test("Titles match across spellings; a REST title seen twice needs two page links; an empty REST list changes nothing")
    func matching() {
        let home = [Self.link("ADA"), Self.link("Divers"), Self.link("Mémoire")]
        let rest = [Self.link("Ada", "/a"), Self.link("memoire", "/m"), Self.link("Divers", "/d1"), Self.link("Divers", "/d2")]
        let completed = ForumListCompletion.complete(home, with: rest)
        #expect(completed.map(\.path) == [home[0].path, home[1].path, "/d2", home[2].path])
        #expect(ForumListCompletion.complete(home, with: []) == home)
        #expect(ForumListCompletion.complete([], with: rest) == rest)
    }

    @Test("An added row goes right after the entry of the REST row before it, or first when it has none")
    func placement() {
        let home = [Self.link("B"), Self.link("D"), Self.link("Z")]
        let rest = [Self.link("A", "/a"), Self.link("B"), Self.link("C", "/c"), Self.link("D"), Self.link("E", "/e")]
        let completed = ForumListCompletion.complete(home, with: rest)
        #expect(completed.map(\.title) == ["A", "B", "C", "D", "E", "Z"])
    }

    // MARK: - The injection table against the captures

    @Test("Every injected sub-forum of a captured category is in its REST list; none is of a category not captured yet")
    func injectionsAgainstCapture() throws {
        let slugs = [1: "Hardware", 2: "OverclockingCoolingModding", 10: "Programmation"]
        var checked = 0
        for entry in Self.captured {
            let (category, file) = (entry.category, entry.file)
            let titles = Set(try Self.rest(file, category: category).map { ForumListCompletion.key($0.title) })
            let slug = try #require(slugs[category])
            for injection in SubforumInjection.all {
                for link in injection.before + injection.after where link.path.hasPrefix("/hfr/\(slug)/") {
                    #expect(titles.contains(ForumListCompletion.key(link.title)), "\(slug) \(link.title)")
                    checked += 1
                }
            }
        }
        // Hardware 1, Overclocking 1, Programmation 14 (PDA and Biblio Links removed).
        #expect(checked == 16)
        #expect(!SubforumInjection.all.flatMap { $0.before + $0.after }.contains { ["PDA", "Biblio Links"].contains($0.title) })
    }

    // MARK: - The client

    private static func run(
        _ replies: [Result<HTTPResponse, NetworkError>],
        forums: [ForumCategory]
    ) async -> (result: Result<[ForumCategory], RESTBrowsingError>, requests: [HTTPRequest]) {
        let transport = MockTransport(replies: replies)
        let result: Result<[ForumCategory], RESTBrowsingError>
        do {
            result = .success(try await RESTBrowsingClient(transport: transport).completingSubforums(of: forums))
        } catch {
            result = .failure(error)
        }
        return (result, await transport.requests)
    }

    @Test("completingSubforums: one captured GET per category with an id, no cookie; a category without id is left as is")
    func client() async throws {
        let forums = try Self.home()
        let chosen = try [1, 2, 10].map { cat in try #require(forums.first { $0.categoryID == .forum(cat) }) }
        let unknown = ForumCategory(categoryID: nil, title: "Nouveau", path: "/hfr/Nouveau/liste_sujet-1.htm", subforums: [Self.link("X")])
        let replies = try Self.captured.map { Result<HTTPResponse, NetworkError>.success(try RESTCapture.response($0.file, id: $0.id)) }
        let run = await Self.run(replies, forums: [chosen[0], unknown, chosen[1], chosen[2]])
        let result = try run.result.get()
        #expect(result.map(\.title) == [chosen[0].title, "Nouveau", chosen[1].title, chosen[2].title])
        #expect(result.map(\.subforums.count) == [15, 1, 7, 27])
        #expect(result[0].path == chosen[0].path && result[3].categoryID == .forum(10))
        #expect(run.requests.map(\.url.absoluteString) == (try Self.captured.map { try Capture.meta($0.id).url }))
        #expect(run.requests.allSatisfy { $0.headers["Cookie"] == nil && $0.redirectPolicy == .doNotFollow })
    }

    @Test("completingSubforums: a failed or refused category keeps the page's list; cancellation, offline and timeout end the call")
    func clientFailures() async throws {
        let forums = try Self.home()
        let cooling = try #require(forums.first { $0.categoryID == .forum(2) })
        let programmation = try #require(forums.first { $0.categoryID == .forum(10) })
        let refused = try RESTCapture.response(RESTCapture.unknownCategory, id: "R57i")
        let answer = try RESTCapture.response(RESTCapture.subcategories10, id: "R285c")
        let url = Self.url
        for failure in [Result<HTTPResponse, NetworkError>.success(refused), .failure(.httpStatus(code: 500, url: url))] {
            let run = await Self.run([failure, .success(answer)], forums: [cooling, programmation])
            let result = try run.result.get()
            #expect(result[0] == cooling)
            #expect(result[1].subforums.count == 27)
        }
        for error in [NetworkError.cancelled, .offline, .timedOut] {
            let run = await Self.run([.failure(error), .success(answer)], forums: [cooling, programmation])
            #expect(throws: RESTBrowsingError.network(error)) { try run.result.get() }
            #expect(run.requests.count == 1)
        }
    }

    private static let url = URL(string: "https://forum.hardware.fr/") ?? URL(fileURLWithPath: "/")
}
