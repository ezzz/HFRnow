import Foundation
import HFRModels
import Testing
@testable import HFRNetwork

struct HFREndpointSearchTests {
    private static let search = "https://forum.hardware.fr/search.php?config=hardwarefr.inc"

    private static func body(_ request: HTTPRequest) -> String {
        request.body.flatMap { String(bytes: $0, encoding: .utf8) } ?? ""
    }

    @Test func globalSearchDefaultsFollowLegacyFieldOrder() throws {
        let request = try HFREndpoint.globalSearch(GlobalSearchQuery(text: "Carte Graphique"), hashCheck: "abc123")
        #expect(request.url.absoluteString == Self.search)
        #expect(request.method == .post)
        #expect(request.headers["Content-Type"] == FormBody.contentType)
        #expect(request.timeout == RequestTimeout.globalSearch)
        #expect(request.redirectPolicy == .follow)
        #expect(Self.body(request) ==
            "hash_check=abc123&cat=13&search=carte+graphique&resSearch=200&orderSearch=0"
            + "&titre=3&searchtype=1&pseud=&daterange=2")
    }

    @Test(arguments: [
        (GlobalSearchQuery.MatchMode.allWords, GlobalSearchQuery.Scope.titleAndContent, "titre=3&searchtype=1"),
        (.anyWord, .title, "titre=1&searchtype=2"),
        (.advanced, .content, "titre=0&searchtype=0")
    ])
    func matchModeAndScope(mode: GlobalSearchQuery.MatchMode, scope: GlobalSearchQuery.Scope, expected: String) throws {
        let query = GlobalSearchQuery(text: "x", category: .forum(1), matchMode: mode, scope: scope)
        #expect(Self.body(try HFREndpoint.globalSearch(query, hashCheck: "h")) ==
            "hash_check=h&cat=1&search=x&resSearch=200&orderSearch=0&\(expected)&pseud=&daterange=2")
    }

    @Test func startDateAddsDateFieldsLast() throws {
        let query = GlobalSearchQuery(text: "x", dateRange: .since(day: 5, month: 3, year: 2021))
        #expect(Self.body(try HFREndpoint.globalSearch(query, hashCheck: "h")) ==
            "hash_check=h&cat=13&search=x&resSearch=200&orderSearch=0&titre=3&searchtype=1&pseud="
            + "&daterange=1&jour=05&mois=03&annee=2021")
    }

    @Test func startDatePadsYear() throws {
        let query = GlobalSearchQuery(text: "x", dateRange: .since(day: 31, month: 12, year: 99))
        #expect(Self.body(try HFREndpoint.globalSearch(query, hashCheck: "h")).hasSuffix("&jour=31&mois=12&annee=0099"))
    }

    @Test(arguments: [(0, 1, 2020), (32, 1, 2020), (1, 0, 2020), (1, 13, 2020), (1, 1, -1), (1, 1, 10000),
                      (31, 2, 2026), (30, 2, 2024), (29, 2, 2023), (31, 4, 2026), (29, 2, 1900)])
    func invalidStartDateIsRefused(day: Int, month: Int, year: Int) {
        let query = GlobalSearchQuery(text: "x", dateRange: .since(day: day, month: month, year: year))
        #expect(throws: NetworkError.self) { try HFREndpoint.globalSearch(query, hashCheck: "h") }
    }

    @Test(arguments: [(29, 2, 2024), (29, 2, 2000), (28, 2, 2023), (30, 4, 2026), (31, 12, 2026)])
    func validEdgeDatesAreAccepted(day: Int, month: Int, year: Int) throws {
        let query = GlobalSearchQuery(text: "x", dateRange: .since(day: day, month: month, year: year))
        _ = try HFREndpoint.globalSearch(query, hashCheck: "h")
    }

    @Test func accentsAndSymbolsArePercentEncodedAsUTF8() throws {
        let request = try HFREndpoint.globalSearch(GlobalSearchQuery(text: "Éléphant & co+"), hashCheck: "a+b")
        #expect(Self.body(request).hasPrefix("hash_check=a%2Bb&cat=13&search=%C3%A9l%C3%A9phant+%26+co%2B&"))
    }

    @Test func emptyHashIsSentAsLegacyDid() throws {
        let request = try HFREndpoint.globalSearch(GlobalSearchQuery(text: "x"), hashCheck: "")
        #expect(Self.body(request).hasPrefix("hash_check=&cat=13&"))
    }

    @Test(arguments: ["", "   ", "\n"])
    func globalSearchRefusesBlankText(text: String) {
        #expect(throws: NetworkError.self) { try HFREndpoint.globalSearch(GlobalSearchQuery(text: text), hashCheck: "h") }
    }

    private static let topic = TopicID(category: .forum(13), topic: 42)

    @Test func topicSearchFreshSearch() throws {
        let query = TopicSearchQuery(topic: Self.topic, word: "ça marche", author: "Marc", formPage: "1")
        let request = try HFREndpoint.topicSearch(query, hashCheck: "tok")
        #expect(request.url.absoluteString == "https://forum.hardware.fr/transsearch.php")
        #expect(request.method == .post)
        #expect(request.redirectPolicy == .doNotFollow)
        #expect(request.timeout == RequestTimeout.topicSearch)
        #expect(Self.body(request) == "hash_check=tok&p=1&post=42&cat=13&word=%C3%A7a+marche&spseudo=Marc&filter=1")
    }

    @Test func topicSearchContinuationAndOptionalFields() throws {
        let continuation = TopicSearchQuery.Continuation(firstNumber: "100", currentNumber: "250")
        let query = TopicSearchQuery(topic: Self.topic, word: "x", filterEnabled: false, continuation: continuation)
        #expect(Self.body(try HFREndpoint.topicSearch(query, hashCheck: "tok")) ==
            "hash_check=tok&post=42&cat=13&word=x&spseudo=&firstnum=100&currentnum=250")
    }

    @Test func topicSearchAuthorOnlyAndEmptyFormPage() throws {
        let query = TopicSearchQuery(topic: Self.topic, word: "", author: "Marc", formPage: "")
        #expect(Self.body(try HFREndpoint.topicSearch(query, hashCheck: "tok")) ==
            "hash_check=tok&post=42&cat=13&word=&spseudo=Marc&filter=1")
    }

    @Test func topicSearchPrivateTopicUsesPriveCategory() throws {
        let query = TopicSearchQuery(topic: TopicID(category: .privateMessages, topic: 8), word: "x")
        #expect(Self.body(try HFREndpoint.topicSearch(query, hashCheck: "t")).contains("&post=8&cat=prive&"))
    }

    @Test func topicSearchRefusesNoCriterionOrNoHash() {
        #expect(throws: NetworkError.self) {
            try HFREndpoint.topicSearch(TopicSearchQuery(topic: Self.topic, word: " ", author: "\n"), hashCheck: "t")
        }
        #expect(throws: NetworkError.self) {
            try HFREndpoint.topicSearch(TopicSearchQuery(topic: Self.topic, word: "x"), hashCheck: "")
        }
    }
}
