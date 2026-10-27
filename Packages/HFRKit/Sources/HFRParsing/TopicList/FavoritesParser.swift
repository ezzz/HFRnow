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
    /// A page where HFR shows a message instead (R12) is an empty page carrying that `notice`: like LOT-022's lists, it cannot
    /// be told from a login wall here (an empty `owntopic=1` list may well be the same page), so the caller decides from its session.
    /// - Throws: `maintenance` for the maintenance page, `malformed` for a page that is neither a list nor a message, or
    ///   whose rows are unreadable or outside a readable category header.
    public static func parse(_ html: String) throws(ListPageFailure) -> FavoritesPage {
        // Page status and the unreadable-rows check are the topic list's: same body id, `.hop` page and row cells.
        let list = try TopicListParser.parseRows(html, pageURL: "/forum1f.php")
        guard let body = list.body else {
            return FavoritesPage(notice: list.page.notice)
        }

        // Legacy walks the rows of `table.main` only (`ObjCFavoritesLoaderWorker.m:103-104`).
        let table = body.firstDescendant(matching: .exact("main"))
        let summaries = Dictionary(uniqueKeysWithValues: list.rows.map { (ObjectIdentifier($0.element), $0.summary) })
        var sections: [FavoriteSection] = []
        var current: FavoriteSection?
        var placed = 0
        for row in (try? table?.getElementsByTag("tr").array()) ?? [] {
            if hasClass("fondForum1fCat", row) {
                if let finished = current { sections.append(finished) }
                current = header(of: row)
            } else if let summary = summaries[ObjectIdentifier(row)], current != nil {
                current?.topics.append(resuming(summary))
                placed += 1
            }
        }
        if let finished = current { sections.append(finished) }

        // A readable row outside a readable category header is a markup change, not a shorter list: never return a partial one
        // (LESSONS 44).
        if placed < list.rows.count {
            throw .malformed("\(list.rows.count - placed) of \(list.rows.count) rows not under a readable category header")
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

    private static func hasClass(_ token: String, _ element: Element) -> Bool {
        (try? element.attr("class"))?.htmlClassTokens.contains { $0 == token } == true
    }
}
