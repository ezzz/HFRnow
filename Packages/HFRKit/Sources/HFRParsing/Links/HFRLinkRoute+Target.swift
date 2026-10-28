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

        var pathAndQuery: String { query.map { path + "?" + $0 } ?? path }

        /// Path, query and fragment as one relative link, the form `HFRURL` reads.
        private var relative: String { fragment.map { pathAndQuery + "#" + $0 } ?? pathAndQuery }

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
