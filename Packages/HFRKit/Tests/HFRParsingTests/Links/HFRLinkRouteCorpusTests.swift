import Foundation
import HFRModels
import Testing
@testable import HFRParsing

/// Every `href` of the committed capture corpus (LOT-001), routed: the shapes the pages really contain.
@Suite("Link router on the capture corpus")
struct HFRLinkRouteCorpusTests {
    /// Distinct `href` values of every captured page, resolved against the forum root; in-page anchors, mailto, javascript
    /// and the like are not URLs the router sees. Entities are decoded by `HFRURL.absolute`.
    static func corpusLinks() throws -> [URL] {
        let directory = try #require(Bundle.module.url(forResource: "captures", withExtension: nil, subdirectory: "Fixtures"))
        let pages = try FileManager.default.contentsOfDirectory(atPath: directory.path).filter { $0.hasSuffix(".html") }
        var links = Set<String>()
        for page in pages {
            let html = try String(contentsOf: directory.appending(path: page), encoding: .utf8)
            for match in html.matches(of: /href="([^"]*)"/) {
                // `#bas` and the like point inside the page being read; they have no route of their own.
                let href = String(match.output.1)
                if !href.hasPrefix("#"), let url = HFRURL.absolute(href) {
                    links.insert(url.absoluteString)
                }
            }
        }
        return links.sorted().compactMap { URL(string: $0) }
    }

    /// First path component, or the first two under `/hfr/`: what tells one kind of page from another.
    static func head(of url: URL) -> String {
        let parts = url.path.split(separator: "/").map { $0.lowercased() }
        guard let first = parts.first else { return "/" }
        guard first == "hfr", parts.count > 1 else { return first }
        if parts[1] == "recherche" { return "hfr/recherche" }
        return parts.last?.hasPrefix("nouveau_") == true ? "hfr/nouveau_*" : "hfr/<forum>"
    }

    /// Forum pages that are links in the corpus but are not routed: other pages of the site, forms, assets, views.
    static let unrouted: Set<String> = [
        "message.php", "user", "viewbbcode.php", "profilebdd.php", "configuration.php", "wikismilies.php", "include",
        "themes", "password.php", "inscription.php", "smilies.php", "editprofil.php", "upload.php", "uploadsmil.php",
        "rss.php", "transactions_reports.php", "forum2.php3", "forum.php", "setperso.php", "passwordchange.php",
        "clearimage.php", "supprperso.php", "hfr/recherche", "hfr/nouveau_*"
    ]

    /// Links of an owned page kind that are deliberately external: the print and single-message views of a topic, and the
    /// favourites page with a filter (`owntopic` 0 and 2) that HFR-PROTOCOL R3 does not document (pending capture).
    static func isKnownUnroutedView(_ url: URL) -> Bool {
        let link = url.absoluteString
        // `forum1.php` with no `cat` at all: which list it names is not documented, so it is not guessed.
        if url.path == "/forum1.php", url.query == "config=hfr.inc" { return true }
        if url.path == "/forum2.php" { return link.contains("print=1") || link.contains("quote_only=1") }
        return url.path == "/forum1f.php" && (link.contains("owntopic=0") || link.contains("owntopic=2"))
    }

    @Test("Every forum link of the corpus is routed, or belongs to a page kind the router does not own")
    func everyLinkIsAccountedFor() throws {
        let links = try Self.corpusLinks()
        var routedKinds = Set<String>()
        var unexpected = Set<String>()
        for url in links where url.host == HFRURL.forumHost {
            let route = HFRLinkRoute.route(for: url)
            if case .external = route {
                if !Self.unrouted.contains(Self.head(of: url)), !Self.isKnownUnroutedView(url) { unexpected.insert(url.absoluteString) }
            } else {
                routedKinds.insert(String(describing: route).prefix { $0 != "(" }.description)
                #expect(!Self.unrouted.contains(Self.head(of: url)), "\(url) is routed but its page kind is listed as not owned")
            }
        }
        #expect(unexpected.isEmpty, "external although it looks like a page the router owns: \(unexpected.sorted().prefix(5))")
        // The corpus holds all of these; a kind that vanishes means the router stopped recognising its shape.
        #expect(routedKinds == ["topic", "privateMessageThread", "topicList", "privateMessageList", "favorites", "profile", "search",
                                "searchResults", "home"], "\(routedKinds.sorted())")
        #expect(links.count > 1000, "\(links.count) distinct links")
    }

    @Test("Topic links of the corpus keep the page and message HFRURL reads from them, on both URL shapes")
    func topicLinksKeepPageAndMessage() throws {
        var canonical = 0
        var forum2 = 0
        for url in try Self.corpusLinks() where url.host == HFRURL.forumHost {
            let link = url.absoluteString
            let isCanonical = url.path.contains("-sujet_")
            guard isCanonical || url.path == "/forum2.php" else { continue }
            let topic: HFRTopicLink
            switch HFRLinkRoute.route(for: url) {
            case .topic(let value), .privateMessageThread(let value): topic = value
            default:
                // Print and quote-only views of a topic are not the topic page.
                #expect(!isCanonical, "\(link) is a canonical topic link")
                #expect(Self.isKnownUnroutedView(url), "\(link)")
                continue
            }
            // `numreponse=M` makes the server pick the page (R25), so such a link names no page.
            let numreponse = HFRURL.numreponse(in: link)
            #expect(topic.page == (numreponse == nil ? HFRURL.page(in: link) : nil), "page of \(link)")
            #expect(topic.anchorPostNumber == HFRURL.anchorPostNumber(in: link), "anchor of \(link)")
            #expect(topic.numreponse == numreponse, "numreponse of \(link)")
            if isCanonical { canonical += 1 } else { forum2 += 1 }
        }
        #expect(canonical > 500 && forum2 > 100, "canonical \(canonical), forum2.php \(forum2)")
    }

    @Test("Lookalike versions of corpus links are external: the same path on another host is never routed")
    func lookalikesOfRealLinks() throws {
        var checked = 0
        for url in try Self.corpusLinks() where url.host == HFRURL.forumHost {
            for host in ["forum.hardware.fr.evil.example", "evil-forum.hardware.fr", "forum.hardware.fr:8443"] {
                var components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
                components.host = host.split(separator: ":").first.map(String.init)
                components.port = host.contains(":") ? 8443 : nil
                let lookalike = try #require(components.url)
                #expect(HFRLinkRoute.route(for: lookalike) == .external(lookalike), "\(lookalike)")
                checked += 1
            }
        }
        #expect(checked > 3000, "\(checked)")
    }
}
