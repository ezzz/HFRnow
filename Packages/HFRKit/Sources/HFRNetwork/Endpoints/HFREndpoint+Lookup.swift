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

extension HFREndpoint {
    /// #714: the profile link of a one-to-one MP row, `profilebdd.php?config=hfr.inc&pseudo=<pseudo>` (HFR-PROTOCOL §6c
    /// "#714 — `profilebdd.php` redirect", `R716a`), not followed: HFR answers one `301` to `/hfr/profil-<id>.htm` and the
    /// caller reads the id with `memberID(inProfileRedirect:)`, so an unknown pseudo (empty id, `R716d`) costs one request.
    ///
    /// The pseudo is percent-encoded (a space is `%20`); surrounding white space is dropped and a blank pseudo is refused.
    public static func profileRedirect(pseudo: String) throws -> HTTPRequest {
        let trimmed = pseudo.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw NetworkError.invalidRequest(reason: "profile lookup needs a pseudo") }
        return try .get(url(path: "/profilebdd.php", query: [("config", config), ("pseudo", trimmed)]), redirectPolicy: .doNotFollow)
    }

    /// The member id a `profileRedirect(pseudo:)` answer names: a 3xx whose `Location` is `/hfr/profil-<id>.htm` on the forum's
    /// own host over HTTPS (`R716a`, `R716c`). Nil for an empty id (`R716d`, unknown pseudo), any other answer or location.
    public static func memberID(inProfileRedirect response: HTTPResponse) -> Int? {
        guard response.isRedirect, let location = response.redirectLocation,
              location.scheme?.lowercased() == "https", location.host()?.lowercased() == "forum.hardware.fr",
              location.port == nil, location.user == nil, location.query == nil,
              let match = location.path(percentEncoded: true).wholeMatch(of: /\/hfr\/profil-([0-9]{1,18})\.htm/)
        else { return nil }
        return Int(match.1)
    }
}
