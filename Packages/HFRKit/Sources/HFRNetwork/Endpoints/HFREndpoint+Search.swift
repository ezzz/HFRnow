import Foundation
import HFRModels

extension HFREndpoint {
    /// S1: global search POST (`ObjCForumSearchWorker.m:141-181`).
    ///
    /// Fields in this order: `hash_check, cat, search, resSearch=200, orderSearch=0, titre, searchtype, pseud="",
    /// daterange` then `jour, mois, annee` only for a start date. The text is lowercased and sent as typed:
    /// the banned-word policy (Q-7) belongs to the caller. The session must be cookie-less (LOT-042); an unknown
    /// `hash_check` may be passed empty, as legacy did when it had none.
    public static func globalSearch(_ query: GlobalSearchQuery, hashCheck: String) throws -> HTTPRequest {
        guard !query.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw NetworkError.invalidRequest(reason: "empty search text")
        }
        var form = FormBody([
            ("hash_check", hashCheck),
            ("cat", query.category.queryValue),
            ("search", query.text.lowercased()),
            ("resSearch", "200"),
            ("orderSearch", "0"),
            ("titre", query.scope.rawValue),
            ("searchtype", query.matchMode.rawValue),
            ("pseud", "")
        ])
        switch query.dateRange {
        case .fromBeginning:
            form.append("daterange", "2")
        case .since(let day, let month, let year):
            guard (0...9999).contains(year), (1...12).contains(month), (1...daysIn(month: month, year: year)).contains(day) else {
                throw NetworkError.invalidRequest(reason: "invalid search start date")
            }
            form.append("daterange", "1")
            form.append("jour", twoDigits(day))
            form.append("mois", twoDigits(month))
            form.append("annee", String(repeating: "0", count: max(0, 4 - String(year).count)) + String(year))
        }
        return try .post(
            url(path: "/search.php", query: [("config", searchConfig)]),
            form: form,
            timeout: RequestTimeout.globalSearch
        )
    }

    /// S3: intra-topic search POST (`ObjCTopicSearchWorker.m:24-52`, `TopicSearchService.swift:42-62`).
    ///
    /// Fields in this order, empty optional ones left out: `hash_check, p, post, cat, word, spseudo, filter=1,
    /// firstnum, currentnum`. Redirects are not followed: the answer's `Location` header is the result.
    public static func topicSearch(_ query: TopicSearchQuery, hashCheck: String) throws -> HTTPRequest {
        let hasWord = !query.word.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let hasAuthor = !query.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        guard hasWord || hasAuthor else { throw NetworkError.invalidRequest(reason: "no search criterion") }
        guard !hashCheck.isEmpty else { throw NetworkError.invalidRequest(reason: "intra-topic search needs hash_check") }
        var form = FormBody([("hash_check", hashCheck)])
        if let formPage = query.formPage, !formPage.isEmpty { form.append("p", formPage) }
        form.append("post", String(query.topic.topic))
        form.append("cat", query.topic.category.queryValue)
        form.append("word", query.word)
        form.append("spseudo", query.author)
        if query.filterEnabled { form.append("filter", "1") }
        if let continuation = query.continuation {
            form.append("firstnum", continuation.firstNumber)
            form.append("currentnum", continuation.currentNumber)
        }
        return try .post(
            url(path: "/transsearch.php"),
            form: form,
            timeout: RequestTimeout.topicSearch,
            redirectPolicy: .doNotFollow
        )
    }

    /// Days in a Gregorian month, so impossible dates such as 31 February are refused.
    private static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: (year % 400 == 0 || (year % 4 == 0 && year % 100 != 0)) ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// Zero-padded two-digit number, without C-style formatting.
    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : String(value)
    }
}
