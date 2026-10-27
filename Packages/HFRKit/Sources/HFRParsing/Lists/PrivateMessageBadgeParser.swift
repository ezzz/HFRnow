import HFRModels
import SwiftSoup

/// Reads the unread private messages count a page announces: the one rule behind the three legacy readers
/// (`ObjCForumsParser.m:516-525` on the home row, `ObjCTopicListParser.m:83-92` on the list header,
/// `MPBackgroundService.swift:115-139` on `cCatTopic red`).
///
/// The result separates the cases legacy conflated (audit A §9 Q7): `nil` when the page shows no private messages entry
/// (logged out, or a page that has none), `0` when it shows the entry without a number (R03, R08-2), else the number
/// (R02: 10, P03f: 1). It counts conversations with a message the member has not read (HFR-PROTOCOL §6c LOT-023).
public enum PrivateMessageBadgeParser {
    /// The count a home page or a logged-in forum list announces.
    ///
    /// The page kind comes from `<body id>`: the home page (`unique__home__listing_category`) carries the entry as a
    /// `tr.cat` row, forum lists as the 3-cell header block. The MP list itself and every other page have none: nil.
    /// - Throws: `.maintenance` when the body starts with a paragraph, `.malformed` when the page cannot be read.
    public static func unreadCount(in html: String) throws(ListPageFailure) -> Int? {
        let document: Document
        do {
            document = try HTMLDocumentLoader.document(from: html)
        } catch {
            throw .malformed("unreadable HTML document")
        }
        guard let body = document.body() else { throw .malformed("page without body") }
        if let first = body.children().first(), first.tagName() == "p" {
            throw .maintenance(TopicListParser.trimmed(first.ownRawText))
        }
        let id = (try? body.attr("id")) ?? ""
        if id == homeBodyID { return countOnHomePage(body) }
        if TopicListParser.isListBody(body) { return countInListHeader(body) }
        return nil
    }

    /// Count from the text of a private messages entry: its first integer, 0 when it has none ("Messages privés").
    static func count(inText text: String) -> Int {
        HFRText.firstInteger(in: text) ?? 0
    }

    /// Home page: the `a.cCatTopic` of the row whose link has `cat=prive` (R02: "Vous avez 10 nouveaux messages privés",
    /// R03: "Envoyer / lire des messages privés"). Absent when logged out (R01).
    static func countOnHomePage(_ body: Element) -> Int? {
        let link = body.descendants(matching: .contains("cCatTopic")).first { element in
            element.tagName() == "a" && ((try? element.attr("href")).flatMap(HFRURL.category(in:)) == .privateMessages)
        }
        return link.map { count(inText: $0.rawText) }
    }

    /// Logged-in forum lists: the first `.none` block with exactly 3 cells, whose middle one reads "Vous avez N nouveau
    /// message privé" (P03f) or "Messages privés" (R08-2). Anonymous lists, the MP list and search results differ: nil.
    static func countInListHeader(_ body: Element) -> Int? {
        // The first `table.none` with exactly 3 cells: not any `.none` element, and an earlier table of another shape must not
        // hide the header (legacy took the first `.none` and gave up when it had another shape).
        let headers = body.descendants(matching: .classToken("none")).filter { $0.tagName() == "table" }.map { table in
            (try? table.getElementsByTag("td").array()) ?? []
        }
        return headers.first { $0.count == 3 }.map { count(inText: $0[1].rawText) }
    }

    private static let homeBodyID = "unique__home__listing_category"
}
