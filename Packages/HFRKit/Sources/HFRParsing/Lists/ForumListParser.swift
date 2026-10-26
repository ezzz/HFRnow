import Foundation
import HFRModels
import SwiftSoup

/// Reads the forum home page (`GET /`, HFR-PROTOCOL R1): the forum categories with their sub-forums, the login state,
/// the `hash_check` token and the unread private message count.
///
/// Ports `ObjCForumsParser.parseForumsFromData:` (`ObjCForumsParser.m:13-529`) without its side effects: the token and the
/// count come back as data, a maintenance page is an error, and the "Apple" category is returned like any other
/// (hiding it for reviewers is app policy, Q-7). Differences from legacy are listed in `docs/lots/LOT-021-forum-list-parser.md`.
public enum ForumListParser {
    /// The home page as models.
    ///
    /// Categories come in page order. `subforums` holds the sub-forum links of the category cell, completed with the known
    /// sub-forums the home page omits (`SubforumInjection`), without the "all" copy of the parent that legacy put first.
    /// The `cat=prive` row is not a category: it only sets `unreadPrivateMessages` (0 when the row shows no number).
    /// A row lacking its category cell, link or title is skipped.
    /// - Throws: `maintenance` when the body starts with a paragraph (the message is its text), `malformed` when the page has
    ///   no forum row, or none that can be read.
    public static func parse(_ html: String) throws(ListPageFailure) -> ForumListPage {
        let document: Document
        do {
            document = try HTMLDocumentLoader.document(from: html)
        } catch {
            throw .malformed("HTML document")
        }
        guard let body = document.body() else { throw .malformed("body") }
        if let message = maintenanceMessage(in: body) { throw .maintenance(message) }

        let hashCheck = hashCheck(in: body)
        var forums: [ForumCategory] = []
        var unreadPrivateMessages: Int?
        let rows = body.descendants(matching: .contains("cat")).filter { $0.tagName() == "tr" }
        for row in rows {
            // One unexpected `tr.cat` must not take the whole home page down: unreadable rows are skipped.
            guard let parsed = try? parseRow(row) else { continue }
            switch parsed {
            case .forum(let category): forums.append(category)
            case .privateMessages(let count): unreadPrivateMessages = count
            }
        }
        guard !forums.isEmpty else {
            throw .malformed(rows.isEmpty ? "no forum row (tr class*=cat)" : "\(rows.count) forum rows, none readable")
        }
        return ForumListPage(
            forums: forums,
            isLoggedIn: hashCheck != nil,
            unreadPrivateMessages: unreadPrivateMessages,
            hashCheck: hashCheck
        )
    }

    // MARK: - Implementation

    /// What a readable `tr.cat` row is.
    private enum Row {
        case forum(ForumCategory)
        case privateMessages(unread: Int)
    }

    /// Reads one row; throws `malformed` naming the missing part.
    private static func parseRow(_ row: Element) throws(ListPageFailure) -> Row {
        let cell = try categoryCell(of: row)
        let topicLink = try require(cell.firstDescendant(matching: .contains("cCatTopic")), "forum link (class*=cCatTopic)")
        let rawHref = try require(nonEmptyAttribute("href", of: topicLink), "forum link href")
        if HFRURL.category(in: rawHref) == .privateMessages {
            return .privateMessages(unread: HFRText.firstInteger(in: textContent(of: topicLink)) ?? 0)
        }
        // Paths are requested with the session later: only forum-relative links are kept (LESSONS 37).
        let href = try require(HFRURL.forumRelativePath(rawHref), "forum link href")
        let path = href == misrouted ? corrected : href
        return .forum(ForumCategory(
            categoryID: categoryID(ofRow: row, path: path),
            title: try title(in: cell),
            path: path,
            subforums: subforums(in: cell)
        ))
    }

    /// The home link of "Achats & Ventes" points at its "Hardware" sub-forum; legacy corrected it to the category's own list
    /// (`ObjCForumsParser.m:69-71`), which is also the path `ForumCatalogue` knows.
    private static let misrouted = "/hfr/AchatsVentes/Hardware/liste_sujet-1.htm"
    private static let corrected = "/hfr/AchatsVentes/liste_sujet-1.htm"

    /// Text of a maintenance page: the body's first node (ignoring blank text) is a `<p>` (`ObjCForumsParser.m:20-31`).
    private static func maintenanceMessage(in body: Element) -> String? {
        let first = body.getChildNodes().first { node in
            guard let text = node as? TextNode else { return true }
            return !text.isBlank()
        }
        guard let paragraph = first as? Element, paragraph.tagName() == "p" else { return nil }
        return textContent(of: paragraph).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Value of the first `hash_check` field when it is not empty: the page is then a logged-in one (`ObjCForumsParser.m:36-43`).
    private static func hashCheck(in body: Element) -> String? {
        guard
            let field = body.firstDescendant(attribute: "name", matching: .exact("hash_check")),
            let value = attribute("value", of: field),
            !value.isEmpty
        else { return nil }
        return value
    }

    /// Second `<td>` of a forum row, which holds the title and the sub-forum links (`ObjCForumsParser.m:54-61`).
    private static func categoryCell(of row: Element) throws(ListPageFailure) -> Element {
        let cells = row.children().array().filter { $0.tagName() == "td" }
        guard cells.count >= 2 else { throw .malformed("forum row with fewer than two cells") }
        return cells[1]
    }

    /// Trimmed text of the first `<b>` of the cell.
    private static func title(in cell: Element) throws(ListPageFailure) -> String {
        let bold = try require(try? cell.getElementsByTag("b").first(), "forum title (b)")
        let title = textContent(of: bold).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty else { throw .malformed("forum title (b)") }
        return title
    }

    /// Links of class `Tableau` in the cell (those without a forum-relative `href` dropped),
    /// completed with the `SubforumInjection`s the page does not already list.
    private static func subforums(in cell: Element) -> [ForumLink] {
        // A sub-forum link without target is dropped, not fatal.
        let links = cell.descendants(matching: .exact("Tableau")).compactMap { node in
            nonEmptyAttribute("href", of: node).flatMap(HFRURL.forumRelativePath).map {
                ForumLink(title: textContent(of: node).trimmingCharacters(in: .whitespacesAndNewlines), path: $0)
            }
        }
        var known = Set(links.map(\.path))
        var result: [ForumLink] = []
        func addNew(_ injected: [ForumLink]) {
            for link in injected where known.insert(link.path).inserted {
                result.append(link)
            }
        }
        var listed = Set<String>()
        for link in links where listed.insert(link.path).inserted {
            let matching = SubforumInjection.all.filter { $0.trigger == link.path }
            matching.forEach { addNew($0.before) }
            result.append(link)
            matching.forEach { addNew($0.after) }
        }
        return result
    }

    /// `cat` id of a forum row: its `id="cat<N>"` (captures `R01`-`R03`), else the catalogue by path.
    private static func categoryID(ofRow row: Element, path: String) -> CategoryID? {
        let rowID = row.id()
        if rowID.hasPrefix("cat"), let id = CategoryID(queryValue: String(rowID.dropFirst(3))), id != .privateMessages {
            return id
        }
        return ForumCatalogue.categoryID(forPath: path)
    }

    /// Attribute value, nil when the attribute is absent.
    private static func attribute(_ name: String, of element: Element) -> String? {
        element.hasAttr(name) ? (try? element.attr(name)) : nil
    }

    /// Attribute value, nil when the attribute is absent or empty: a link without target cannot open a topic list.
    private static func nonEmptyAttribute(_ name: String, of element: Element) -> String? {
        attribute(name, of: element).flatMap { $0.isEmpty ? nil : $0 }
    }

    /// `textContent` of an element: every text node below it, entities decoded, whitespace untouched (libxml2 `allContents`).
    private static func textContent(of element: Element) -> String {
        element.getChildNodes().reduce(into: "") { text, node in
            if let textNode = node as? TextNode {
                text += textNode.getWholeText()
            } else if let child = node as? Element {
                text += textContent(of: child)
            }
        }
    }

    /// A found element, or `malformed` naming what was looked for.
    private static func require<Value>(_ value: Value?, _ what: String) throws(ListPageFailure) -> Value {
        guard let value else { throw .malformed(what) }
        return value
    }
}
