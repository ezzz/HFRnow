import Foundation
import HFRModels

extension HFRLinkRoute {
    /// A link whose shape or values are not known: it becomes `.external`, never a guessed route.
    struct Refused: Error {}

    /// The parts of a link that is known to point at the forum, split so the helpers of `HFRURL` can read them.
    struct Target {
        /// Percent-encoded path, so an encoded slash cannot create a segment.
        let path: String
        let query: String?
        let fragment: String?

        /// Nil unless `url` is `http`/`https` on exactly `forum.hardware.fr`, without user info or an explicit port
        /// (LESSONS 37: `http://forum.hardware.fr:80/` and `https://forum.hardware.fr@evil.example/` are both refused).
        init?(_ url: URL) {
            guard
                let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
                let scheme = components.scheme?.lowercased(), scheme == "https" || scheme == "http",
                components.percentEncodedHost?.lowercased() == HFRURL.forumHost,
                components.user == nil, components.password == nil, components.port == nil
            else { return nil }
            path = components.percentEncodedPath
            query = components.percentEncodedQuery
            fragment = components.percentEncodedFragment
        }

        /// Path, query and fragment as one relative link, the form `HFRURL` reads.
        private var relative: String {
            let pathAndQuery = query.map { path + "?" + $0 } ?? path
            return fragment.map { pathAndQuery + "#" + $0 } ?? pathAndQuery
        }

        /// Parameters of a global search results page, as `forum1.php` links carry them (R50b, first page and pager).
        /// The value says how it is checked: digits only (false), or free text (true: the terms, and `config`, already checked).
        private static let searchParameters: [String: Bool] = [
            "config": true, "cat": false, "page": false, "subcat": false, "sondage": false, "owntopic": false, "trash": false,
            "trash_post": false, "moderation": false, "new": false, "orderSearch": false, "recherches": false, "resSearch": false,
            "jour": false, "mois": false, "annee": false, "titre": false, "daterange": false, "searchtype": false,
            "searchall": false, "nojs": false, "subcatgroup": false, "search": true, "pseud": true, "post_cat_list": true
        ]

        /// A search results link rebuilt from the known search parameters only, so a link written by someone else cannot
        /// make the account session replay an arbitrary query. Unknown parameters are dropped, repeated ones keep their first
        /// value (the pager repeats `cat` and `trash`), a numeric one that is not digits refuses the link.
        func searchResultsPath() throws -> String {
            var seen = Set<String>()
            var pairs: [String] = []
            for item in HFRURL.decodingAmpersands(query ?? "").split(separator: "&") {
                let pair = item.split(separator: "=", maxSplits: 1, omittingEmptySubsequences: false)
                let name = String(pair[0])
                guard let isText = Self.searchParameters[name], seen.insert(name).inserted else { continue }
                let value = pair.count > 1 ? String(pair[1]) : ""
                guard isText || value.utf8.allSatisfy({ (48...57).contains($0) }) else { throw Refused() }
                pairs.append(name + "=" + value)
            }
            return "/forum1.php?" + pairs.joined(separator: "&")
        }

        private func value(_ name: String) -> String? { HFRURL.queryValue(named: name, in: relative) }

        func has(_ name: String) -> Bool { value(name) != nil }

        /// `config` must be absent or `hfr.inc`: another configuration is another forum, not routed.
        func requireForumConfig() throws {
            if let config = value("config"), config != "hfr.inc" { throw Refused() }
        }

        /// `cat`, required; `cat=0` is the "no forum" value of moderation links and is never a forum.
        func category() throws -> CategoryID {
            guard let raw = value("cat"), let category = CategoryID(queryValue: raw), category != .forum(0) else {
                throw Refused()
            }
            return category
        }

        /// A positive ASCII integer; absent or empty is `nil` (HFR writes `page=` and `subcat=` that way), anything else throws.
        func positive(_ name: String) throws -> Int? {
            guard let raw = value(name), !raw.isEmpty else { return nil }
            guard let number = HFRURL.positiveInteger(raw) else { throw Refused() }
            return number
        }

        /// Message number of `numreponse=`: absent, empty and `0` mean none (`Common.swift:2549-2553`).
        func numreponse() throws -> Int? {
            value("numreponse") == "0" ? nil : try positive("numreponse")
        }

        /// Message number of a `#t<numreponse>` fragment.
        var anchorPostNumber: Int? { HFRURL.anchorPostNumber(in: relative) }

        /// `subcat=` of a list link: absent, empty and `0` mean the whole forum.
        func subcategory() throws -> HFRSubcategory? {
            value("subcat") == "0" ? nil : try positive("subcat").map { .id($0) }
        }

        /// `owntopic=`: absent or empty is `.all`; a value outside `allowed` throws.
        func filter(allowed: Set<TopicListFilter>) throws -> TopicListFilter {
            let raw = value("owntopic") ?? ""
            guard
                raw.isEmpty || (raw.utf8.count == 1 && raw.utf8.allSatisfy { (48...57).contains($0) }),
                let filter = raw.isEmpty ? .all : Int(raw).flatMap(TopicListFilter.init(rawValue:)),
                allowed.contains(filter)
            else { throw Refused() }
            return filter
        }

        /// Views of a topic that are not the plain page: print view and the single-message quote view (captures R21).
        func requirePlainTopicView() throws {
            for name in ["print", "quote_only", "trash", "trash_post"] {
                if let raw = value(name), !raw.isEmpty, raw != "0" { throw Refused() }
            }
        }
    }
}
