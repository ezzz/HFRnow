import Foundation

extension HFREndpoint {
    /// Minimum length of a smiley search, counted on the trimmed text (`SmileySearchService.swift:15`).
    public static let smileySearchMinimumLength = 3

    /// R7: smiley search (`SmileySearchService.swift:12-42`).
    ///
    /// Words are split on whitespace and joined by one space; with `requireAll` each word gets a leading `+`
    /// (legacy `smileySearchQuery`, `AnswerView.swift:1308-1318`), and extra leading `+` are dropped first.
    /// The value is percent-encoded, so a space is `%20` and a `+` is `%2B`.
    public static func smileySearch(_ text: String, requireAll: Bool = false) throws -> HTTPRequest {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= smileySearchMinimumLength else {
            throw NetworkError.invalidRequest(reason: "smiley search needs at least \(smileySearchMinimumLength) characters")
        }
        let words = trimmed.split(whereSeparator: \.isWhitespace).map { word in
            let bare = word.drop { $0 == "+" }
            return requireAll ? "+" + bare : String(bare)
        }
        return try .get(url(path: "/message-smi-mp-aj.php", query: [
            ("config", config), ("findsmilies", words.joined(separator: " "))
        ]))
    }

    /// R54: the wiki entry of a smiley, `wikismilies.php?config=hfr.inc&detail=<code>` (`SmileyAlertView.m:150-152`).
    ///
    /// The code is percent-encoded like every query value, `[:name]` → `%5B%3Aname%5D` as in `R54`; legacy encoded it
    /// with `URLPathAllowedCharacterSet`, which leaves `:` raw. Surrounding white space is dropped; a blank code is refused.
    public static func smileyWiki(code: String) throws -> HTTPRequest {
        let trimmed = code.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NetworkError.invalidRequest(reason: "smiley wiki needs a code") }
        return try .get(url(path: "/wikismilies.php", query: [("config", config), ("detail", trimmed)]))
    }

    /// E1: the JSON REST API (`/webservices/rest_api.php?uri=…`), reported by redface2 and still to verify (HFR-PROTOCOL §7).
    ///
    /// `uri` is the resource path, for example `forums/hardwarefr/categories/`; `/` stays literal, other reserved
    /// characters are percent-encoded. `page` and `resultsPerPage` are appended in that order when given.
    public static func rest(uri: String, page: Int? = nil, resultsPerPage: Int? = nil) throws -> HTTPRequest {
        guard !uri.isEmpty else { throw NetworkError.invalidRequest(reason: "empty REST uri") }
        var query = [(name: "uri", value: uri)]
        if let page {
            try requirePage(page)
            query.append((name: "page", value: String(page)))
        }
        if let resultsPerPage {
            guard resultsPerPage >= 1 else { throw NetworkError.invalidRequest(reason: "results per page must be 1 or more") }
            query.append((name: "results_per_page", value: String(resultsPerPage)))
        }
        return try .get(url(path: "/webservices/rest_api.php", query: query, literals: [UInt8(ascii: "/")]))
    }
}
