import HFRModels
import SwiftSoup

/// Parses the favourites page (`GET /forum1f.php?owntopic={1|3}`, HFR-PROTOCOL R3): one `tr.fondForum1fCat` header per
/// category, each followed by its `tr.sujet.ligne_booleen` topic rows, which share the topic list markup.
///
/// Port of `-[ObjCFavoritesLoaderWorker parseFavoritesFromData:]` (`ObjCFavoritesLoaderWorker.m:74-139`) and
/// `Favorite.m:31-210`, as a pure function: the badge and the token come back as data. Differences from legacy are listed in
/// `docs/lots/LOT-024-favourites-parser.md`.
public enum FavoritesParser {
    /// Parses the favourites page.
    ///
    /// Sections come in page order. A page with the list body and no row is an account without favourite: no section.
    /// - Throws: `maintenance` for the maintenance page, `notAuthenticated` for HFR's message page, which this URL serves
    ///   only to logged-out visitors (an empty list keeps the list body, R11, P03e), `malformed` for a page that is neither,
    ///   or whose rows are all unreadable or outside any readable category header.
    public static func parse(_ html: String) throws(ListPageFailure) -> FavoritesPage {
        // Page status and the all-rows-unreadable check are the topic list's: same body id, `.hop` page and row cells.
        let list = try TopicListParser.parseRows(html, pageURL: "/forum1f.php")
        if let notice = list.page.notice { throw .notAuthenticated(notice) }
        let document: Document
        do {
            document = try HTMLDocumentLoader.document(from: html)
        } catch {
            throw .malformed("unreadable HTML document")
        }
        guard let body = document.body() else { throw .malformed("page without body") }

        // Rows are read again here, per section, so that each one knows its category.
        var sections: [FavoriteSection] = []
        var current: FavoriteSection?
        var placed = 0
        for row in (try? body.getElementsByTag("tr").array()) ?? [] {
            if hasClass("fondForum1fCat", row) {
                if let finished = current { sections.append(finished) }
                current = header(of: row)
            } else if
                let section = current,
                isTopicRow(row),
                let summary = TopicListRowParser.summary(from: row, pageCategory: section.categoryID) {
                current?.topics.append(resuming(summary))
                placed += 1
            }
        }
        if let finished = current { sections.append(finished) }

        // Rows were readable but no category header was: a markup change, not an empty favourites list (LESSONS 44).
        if !list.rows.isEmpty && placed == 0 {
            throw .malformed("\(list.rows.count) rows, none under a readable category header")
        }
        return FavoritesPage(
            sections: sections,
            unreadPrivateMessages: list.page.unreadPrivateMessages,
            hashCheck: ForumListParser.hashCheck(in: body)
        )
    }

    /// The category of a header row: its `a.cHeader` link (`Favorite.m:33-45`); nil when it has no usable link.
    private static func header(of row: Element) -> FavoriteSection? {
        guard
            let link = row.firstDescendant(matching: .classToken("cHeader")),
            link.hasAttr("href"),
            let path = (try? link.attr("href")).flatMap(HFRURL.forumRelativePath)
        else { return nil }
        return FavoriteSection(
            forum: ForumLink(title: TopicListParser.trimmed(link.rawText), path: path),
            categoryID: HFRURL.category(in: path)
        )
    }

    /// A favourites row opens where the member stopped: `path` is the flag link, else the last post (`Favorite.m:163-178`),
    /// the title link moves to `firstPagePath` (`:101-102`), and the page comes from that path (`:181-199`).
    /// The read state is unknown: legacy's "viewed unless flagged" is not what the page says (LOT-010).
    private static func resuming(_ summary: TopicSummary) -> TopicSummary {
        var row = summary
        let resume = summary.flagPath ?? summary.lastPost?.path
        row.firstPagePath = summary.path
        row.path = resume ?? summary.path
        row.currentPage = resume.flatMap(HFRURL.page(in:))
        row.readState = .unknown
        return row
    }

    /// `tr.sujet.ligne_booleen`, as `TopicListParser.rowElements` selects rows.
    private static func isTopicRow(_ row: Element) -> Bool {
        hasClass("ligne_booleen", row) && hasClass("sujet", row)
    }

    private static func hasClass(_ token: String, _ element: Element) -> Bool {
        (try? element.attr("class"))?.htmlClassTokens.contains { $0 == token } == true
    }
}
