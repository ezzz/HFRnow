import Foundation
import HFRModels
import SwiftSoup

/// One `tr.sujet.ligne_booleen` row of a list page (`ObjCTopicListParser.m:270-467`).
///
/// Cells are found by class token (`sujetCase1` … `sujetCase9`); legacy mixed exact and substring class matches,
/// which select the same cells on every captured page (substring `sujetCase1` would also match `sujetCase10`).
/// Internal so the favourites parser (LOT-024) can reuse it on its rows and override what differs there.
enum TopicListRowParser {
    /// The row's summary, or nil when it has no title link to a forum path (legacy raised on such a row and lost the page).
    static func summary(from row: Element, pageCategory: CategoryID?) -> TopicSummary? {
        let cells = cellIndex(of: row)
        let cell = { (name: String) in cells[name] }
        guard
            let titleCell = cell("sujetCase3"),
            let titleLinks = try? titleCell.getElementsByTag("a").array(),
            let path = titleLinks.first.flatMap(href).flatMap(HFRURL.forumRelativePath)
        else { return nil }

        let snippet = titleCell.firstDescendant(matching: .classToken("s1"))
        // A last-page link whose target is refused counts as absent, so the row falls back to one page entirely.
        let lastPageLink = cell("sujetCase4").flatMap(firstLink).flatMap { linkPath($0) == nil ? nil : $0 }
        let flagLink = cell("sujetCase5").flatMap(firstLink)
        let searchHit = snippet.flatMap { snippet in
            titleLinks.dropFirst().first.flatMap(href).flatMap(HFRURL.forumRelativePath).map {
                SearchHit(postPath: $0, snippet: TopicListParser.trimmed(snippet.rawText))
            }
        }
        let lastPost = cell("sujetCase9").flatMap(lastPost(in:))
        let rowLinks = [path, lastPageLink.flatMap(linkPath), lastPost?.path, flagLink.flatMap(linkPath), searchHit?.postPath]

        return TopicSummary(
            topicID: topicID(links: rowLinks.compactMap(\.self), titlePath: path, pageCategory: pageCategory),
            title: title(in: titleCell, link: titleLinks[0], isSearchResult: snippet != nil),
            path: path,
            repliesCount: cell("sujetCase7").flatMap { HFRText.firstInteger(in: $0.rawText) } ?? 0,
            pageCount: lastPageLink.flatMap { HFRText.firstInteger(in: $0.rawText) } ?? 1,
            lastPagePath: lastPageLink.flatMap(linkPath),
            lastPost: lastPost,
            starterOrInterlocutors: cell("sujetCase6").map(starter(in:)) ?? "",
            flag: flagLink.flatMap(flag(of:)),
            flagPath: flagLink.flatMap(linkPath),
            currentPage: flagLink.flatMap(linkPath).flatMap(HFRURL.page(in:)),
            readState: readState(of: cell("sujetCase1")),
            isSticky: hasClass("ligne_sticky", row),
            isClosed: !titleCell.descendants(attribute: "alt", matching: .exact("closed")).isEmpty,
            isPoll: isPoll(row),
            searchHit: searchHit
        )
    }

    // MARK: - Cells

    /// Title as HFR prints it, trimmed: the whole title cell (`[non lu]` marker of MP rows included, `:320-321`), or
    /// the title link alone on search results, whose cell also holds the matching message (`:309-320`).
    private static func title(in cell: Element, link: Element, isSearchResult: Bool) -> String {
        guard isSearchResult else { return TopicListParser.trimmed(cell.rawText) }
        let exact = cell.firstDescendant(matching: .classToken("cCatTopic")) ?? link
        return TopicListParser.trimmed(exact.rawText)
    }

    /// Topic starter, or interlocutor(s) on the MP list: the profile link, the `span` "Interlocuteurs multiples"
    /// (R13u1), or the plain text anonymous pages print (R04), which legacy ignored (`:391-403`).
    /// U+200B inserted by HFR in long pseudos is kept (LOT-002 RC2.6).
    private static func starter(in cell: Element) -> String {
        let source = firstChild(tag: "a", of: cell) ?? firstChild(tag: "span", of: cell) ?? cell
        return TopicListParser.trimmed(source.rawText)
    }

    /// Last post from the first child of `sujetCase9`: a link whose own text is the date and whose `<b>` is the author.
    private static func lastPost(in cell: Element) -> LastPost? {
        guard let link = cell.children().first(), link.tagName() == "a", let path = linkPath(link) else { return nil }
        let author = firstChild(tag: "b", of: link)?.rawText ?? ""
        return LastPost(author: author, path: path, date: HFRDate.firstDate(in: link.ownRawText))
    }

    /// Flag colour from the image file name (`:345-355`); a link with another image has a path but no colour.
    private static func flag(of link: Element) -> TopicFlag? {
        guard let source = firstChild(tag: "img", of: link).flatMap({ try? $0.attr("src") }) else { return nil }
        if source.contains("flag0.gif") { return .red }
        if source.contains("flag1.gif") { return .blue }
        if source.contains("favoris.gif") { return .yellow }
        return nil
    }

    /// `alt="On"` on the `sujetCase1` image means unread replies (`:374-388`); any other image or none means read.
    /// Anonymous pages mark every row `On` (`closedb_new.gif`, R04): read state is only meaningful when logged in.
    private static func readState(of cell: Element?) -> TopicReadState {
        let image = cell.flatMap { firstChild(tag: "img", of: $0) }
        return (try? image?.attr("alt")) == "On" ? .unread : .read
    }

    /// Any row image named `sondage.gif`. The live icon is `…/images_forum/1/sondage.gif` in `sujetCase2` (R04);
    /// legacy matched `…/images/defaut/sondage.gif` only and never found a poll (LOT-002 RC2.3).
    private static func isPoll(_ row: Element) -> Bool {
        let images = (try? row.getElementsByTag("img").array()) ?? []
        return images.contains { image in
            guard let source = try? image.attr("src") else { return false }
            return source.split(separator: "/").last.map { $0.lowercased() == "sondage.gif" } ?? false
        }
    }

    /// Category and topic from the first row link carrying `cat=` and `post=` (logged-in, MP and search links);
    /// else the topic of the canonical title path `/hfr/<category>/…-sujet_<post>_<page>.htm` with the category of
    /// its first segment (forum catalogue), or of the page.
    private static func topicID(links: [String], titlePath: String, pageCategory: CategoryID?) -> TopicID? {
        if let identified = links.lazy.compactMap(HFRURL.topicID(in:)).first {
            return identified
        }
        guard let topic = HFRURL.canonicalTopicPath(in: titlePath)?.topic else { return nil }
        let segments = titlePath.split(separator: "/", omittingEmptySubsequences: true)
        let catalogued = segments.count > 2 && segments[0] == "hfr"
            ? ForumCatalogue.categoryID(forPath: "/hfr/\(segments[1])/liste_sujet-1.htm")
            : nil
        return (catalogued ?? pageCategory).map { TopicID(category: $0, topic: topic) }
    }

    // MARK: - Helpers

    /// First descendant per `sujetCase…` class token, in one walk of the row (a lookup per cell walked the row
    /// eight times and dominated the parse: 0.6 ms per row in release on R04).
    private static func cellIndex(of row: Element) -> [String: Element] {
        var cells: [String: Element] = [:]
        for element in (try? row.getAllElements().array().dropFirst()) ?? [] {
            guard element.hasAttr("class"), let classes = try? element.attr("class") else { continue }
            for token in classes.htmlClassTokens where token.hasPrefix("sujetCase") && cells[String(token)] == nil {
                cells[String(token)] = element
            }
        }
        return cells
    }

    private static func firstChild(tag: String, of element: Element) -> Element? {
        (try? element.getElementsByTag(tag).array())?.first { $0 !== element }
    }

    private static func firstLink(in element: Element) -> Element? {
        firstChild(tag: "a", of: element)
    }

    private static func href(_ element: Element) -> String? {
        element.hasAttr("href") ? try? element.attr("href") : nil
    }

    private static func linkPath(_ element: Element) -> String? {
        href(element).flatMap(HFRURL.forumRelativePath)
    }

    private static func hasClass(_ token: String, _ element: Element) -> Bool {
        (try? element.attr("class"))?.htmlClassTokens.contains { $0 == token } == true
    }
}
