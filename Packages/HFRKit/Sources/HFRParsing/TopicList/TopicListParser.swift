import Foundation
import HFRModels
import SwiftSoup

/// Parses a topic list page: a forum or sub-forum list, a filtered (`owntopic`) list, the private messages list
/// or the global search results (HFR-PROTOCOL R2, R4, S2). All of them share the same row markup.
///
/// Port of `-[ObjCTopicListParser parseData:currentURL:]` (`ObjCTopicListParser.m:59-470`), as a pure function:
/// no side effects, no display strings (relative dates, "TU" rewrite), typed failures instead of `statusInfo` and
/// exceptions. Differences from legacy are listed in `docs/lots/LOT-022-topic-list-parser.md`.
public enum TopicListParser {
    /// Parses a list page.
    ///
    /// - Parameters:
    ///   - html: The page as served (UTF-8 text).
    ///   - pageURL: The URL the page was served from, after redirects, absolute or forum-relative. It names the
    ///     current page when the pager points back to it, and gives the page number when the page has no pager.
    /// - Returns: The rows, pagination, tabs and header facts. A page where HFR shows a message instead of a list
    ///   (an empty filter or search) is an empty page carrying that `notice`, not an error.
    /// - Throws: `ListPageFailure.maintenance` for the maintenance page, `.notAuthenticated` for a `.hop` message
    ///   served for the MP list, `.malformed` for a page that is neither a list nor an HFR message, or whose rows are
    ///   all unreadable.
    public static func parse(_ html: String, pageURL: String) throws(ListPageFailure) -> TopicListPage {
        try parseRows(html, pageURL: pageURL).page
    }

    /// Same as `parse`, plus each row's element next to its summary, so the private messages (LOT-023) and
    /// favourites (LOT-024) parsers can read the cells this parser does not model.
    static func parseRows(_ html: String, pageURL: String) throws(ListPageFailure) -> ParsedTopicList {
        let document: Document
        do {
            document = try HTMLDocumentLoader.document(from: html)
        } catch {
            throw .malformed("unreadable HTML document")
        }
        guard let body = document.body() else { throw .malformed("page without body") }
        let pagePath = HFRURL.forumRelativePath(pageURL)

        // A list page has `<body id="…__topics_listing__…">` (R04, R13a, R50b); HFR's message pages have a bare `<body>`
        // (`:67-81`). Legacy took any `id` as a list; another page (login, topic) would then pass for an empty list.
        guard isListBody(body) else {
            return try messagePage(body: body, pagePath: pagePath)
        }

        let tabContainer = body.firstDescendant(matching: .classToken("cadreonglet"))
        let category = pageCategory(in: body, tabs: tabContainer)
        let elements = rowElements(in: body)
        var rows: [ParsedTopicRow] = []
        for element in elements {
            if let summary = TopicListRowParser.summary(from: element, pageCategory: category) {
                rows.append(ParsedTopicRow(element: element, summary: summary))
            }
        }
        // One unreadable row is skipped (D11); a page whose rows are all unreadable is a markup change, not an empty list.
        if !elements.isEmpty && rows.isEmpty {
            throw .malformed("\(elements.count) rows, none readable")
        }
        let page = TopicListPage(
            topics: rows.map(\.summary),
            navigation: TopicListPager.navigation(in: body, pagePath: pagePath),
            tabs: tabContainer.map(tabs(in:)) ?? TopicListTabs(),
            categoryID: category,
            newTopicPath: link(in: body, id: "md_btn_new_topic"),
            unreadPrivateMessages: unreadPrivateMessages(in: body)
        )
        return ParsedTopicList(page: page, rows: rows)
    }

    // MARK: - Page parts

    /// `<section>__topics_listing__<page kind>`: the middle segment of the `id` names the template.
    static func isListBody(_ body: Element) -> Bool {
        guard let id = try? body.attr("id") else { return false }
        let segments = id.split(separator: "__", omittingEmptySubsequences: false)
        return segments.count == 3 && segments[1] == "topics_listing" && !segments[0].isEmpty && !segments[2].isEmpty
    }

    /// Rows are `<tr class="sujet ligne_booleen …">` (legacy: class containing `sujet ligne_booleen`, `:254`).
    static func rowElements(in body: Element) -> [Element] {
        body.descendants(matching: .classToken("ligne_booleen")).filter { element in
            (try? element.attr("class"))?.htmlClassTokens.contains("sujet") == true
        }
    }

    /// A page without the list body: maintenance (`<p>` first, `:70-73`) or a `.hop` message (`:75-76`), whose own text
    /// is the message (legacy `contents`; R50c also holds a "Retour à la page précédente" link, left out).
    ///
    /// Legacy reported every `.hop` page as "not authenticated". On the MP list it can only be a login wall, since an empty
    /// MP list keeps the list body (R13c): it throws `.notAuthenticated`. Elsewhere every captured instance is an empty
    /// result, logged in or not (R08-1, R08-3, R50c; LOT-002 RC2.4), and the page has no header that could tell a wall
    /// apart: it becomes an empty page carrying the message, and callers treat `notice != nil` as "no list".
    private static func messagePage(body: Element, pagePath: String?) throws(ListPageFailure) -> ParsedTopicList {
        if let first = body.children().first(), first.tagName() == "p" {
            throw .maintenance(trimmed(first.ownRawText))
        }
        guard let hop = body.firstDescendant(matching: .classToken("hop")) else {
            throw .malformed("page without list body or message")
        }
        let message = trimmed(hop.ownRawText)
        if pagePath.flatMap(HFRURL.category(in:)) == .privateMessages {
            throw .notAuthenticated(message)
        }
        let navigation = PageNavigation(current: pagePath.flatMap(TopicListPager.pageNumber(inPagePath:)) ?? 1)
        return ParsedTopicList(page: TopicListPage(navigation: navigation, notice: message), rows: [])
    }

    /// Category of the list: the search tab's `cat=` (legacy, logged in only, `:116-131`), else the header search form's
    /// hidden `cat` input, which every captured list page carries (`13`, `12`, `10`, `prive`).
    static func pageCategory(in body: Element, tabs: Element?) -> CategoryID? {
        if
            let tabs,
            let search = tabs.firstDescendant(attribute: "id", matching: .exact("onglet9")),
            let category = (try? search.attr("href")).flatMap(HFRURL.category(in:)) {
            return category
        }
        guard let form = body.firstDescendant(attribute: "id", matching: .exact("fastsearch")) else { return nil }
        let input = form.descendants(attribute: "name", matching: .exact("cat")).first { $0.tagName() == "input" }
        return (try? input?.attr("value")).flatMap { CategoryID(queryValue: $0) }
    }

    /// The four filter tabs of `div.cadreonglet`, shown to logged-in members only (`:139-168`).
    private static func tabs(in container: Element) -> TopicListTabs {
        TopicListTabs(
            all: link(in: container, id: "onglet1"),
            favorites: link(in: container, id: "onglet2"),
            flagBlue: link(in: container, id: "onglet3"),
            flagRed: link(in: container, id: "onglet4")
        )
    }

    /// Unread private messages from the header block `table.none` (`:83-92`).
    ///
    /// Logged-in forum lists show three cells; the middle one reads "Vous avez N nouveau(x) message(s) privé(s)" (P03f)
    /// or just "Messages privés" when there is none (R08-2), which gives 0. Anonymous pages, the MP list and the search
    /// results have another shape and give nil. Shared header logic for LOT-023's badge parser.
    static func unreadPrivateMessages(in body: Element) -> Int? {
        guard let block = body.firstDescendant(matching: .classToken("none")) else { return nil }
        let cells = (try? block.getElementsByTag("td").array()) ?? []
        guard cells.count == 3 else { return nil }
        return HFRText.firstInteger(in: cells[1].rawText) ?? 0
    }

    /// Forum-relative `href` of the descendant with this `id`.
    private static func link(in element: Element, id: String) -> String? {
        guard let target = element.firstDescendant(attribute: "id", matching: .exact(id)) else { return nil }
        return (try? target.attr("href")).flatMap(HFRURL.forumRelativePath)
    }

    /// Trims Unicode `White_Space` characters (spaces including U+00A0, tabs, line breaks), as legacy's
    /// `whitespaceAndNewlineCharacterSet` did. U+200B is kept: it is not white space, and HFR puts it inside pseudos
    /// (LOT-002 RC2.6). Foundation's `whitespacesAndNewlines` strips it on Linux, so it is not used here.
    static func trimmed(_ text: String) -> String {
        let isSpace = { (character: Character) in character.unicodeScalars.allSatisfy(\.properties.isWhitespace) }
        guard let first = text.firstIndex(where: { !isSpace($0) }), let last = text.lastIndex(where: { !isSpace($0) }) else {
            return ""
        }
        return String(text[first...last])
    }
}
