import HFRModels
import SwiftSoup

/// Pagination of a list page: the `fondForum1PagesHaut` header row (`ObjCTopicListParser.m:172-252`).
///
/// Markup (R04, R05a, R05b, R13u1, R50b): `div.left` holds `<b>Page :</b>`, then one entry per page in the window,
/// the current page as `<b>N</b>` and the others as `a.cHeader` or `span.md_cryptlink…` (obfuscated from page 2 on);
/// two `div.pagepresuiv` hold "Page Suivante" and "Page Précédente", disabled as `span.cFondu`.
/// The window shows pages 1-10, then tens, then hundreds around the current page, so `last` is the last page the pager
/// links to, not the page count of the forum (LOT-002 RC2.1). `isExact` is set only when the window cannot hide pages
/// (LOT-167): see ``windowSize``.
enum TopicListPager {
    /// Navigation of the page; `pagePath` is the forum-relative URL the page was served from.
    ///
    /// Entries are classified by content (an element whose text is a page number), not by legacy's child index 2 and
    /// last child, which counted text nodes and raised on short pagers. The current page is the bold entry; without a
    /// pager it comes from `pagePath`, else 1. An entry for the current page links to `pagePath`, as legacy did.
    static func navigation(in body: Element, pagePath: String?) -> PageNavigation {
        let urlPage = pagePath.flatMap(pageNumber(inPagePath:))
        guard let header = body.firstDescendant(matching: .classToken("fondForum1PagesHaut")) else {
            // A list without a pager header is one page: every captured empty or single-row list has none (R08-1, R13c).
            return PageNavigation(current: urlPage ?? 1, isExact: true)
        }
        let entries = header.firstDescendant(matching: .classToken("left")).map(pageEntries(in:)) ?? []
        let current = entries.first { $0.element.tagName() == "b" }?.number ?? urlPage ?? 1
        var navigation = PageNavigation(current: current)
        if let first = entries.first, let last = entries.last {
            navigation.first = first.number
            navigation.last = last.number
            navigation.firstPath = first.number == current ? pagePath : linkTarget(of: first.element)
            navigation.lastPath = last.number == current ? pagePath : linkTarget(of: last.element)
            navigation.isExact = isExactCount(of: entries.map(\.number))
        }
        let arrows = header.descendants(matching: .classToken("pagepresuiv"))
        if arrows.count == 2 {
            navigation.nextPath = linkTarget(of: arrows[0])
            navigation.previousPath = linkTarget(of: arrows[1])
        }
        return navigation
    }

    /// HFR lists pages 1-10 one by one, then only tens (R04: `1 … 10 20 30`), so a pager that stops before 10 cannot hide
    /// a page, while one that reaches 10 or skips a number can (R05a, R05b: jumps by tens and hundreds).
    private static let windowSize = 10

    /// True when the pager entries are 1, 2, … N with N below the window size: its last page is then the page count.
    ///
    /// Pager shapes with N < 10 are captured (R08-2: 1, R50b: 1-2, R13u1: 1-7); that nothing hides behind them is inferred
    /// from the window starting with pages 1-10, hence the strict bound (LOT-167).
    static func isExactCount(of pageNumbers: [Int]) -> Bool {
        guard let last = pageNumbers.last, last < windowSize else { return false }
        return pageNumbers == Array(1...last)
    }

    /// Page number named by a list URL: `page=N`, else `liste_sujet-N.htm`; nil otherwise.
    ///
    /// Legacy fell back to the last digit of the URL (`:94-114`), so a search URL ending in `moderation=0` meant
    /// page 1 by chance (LOT-002 RC2.7); here such a URL names no page.
    static func pageNumber(inPagePath path: String) -> Int? {
        if let page = HFRURL.queryValue(named: "page", in: path).flatMap(HFRURL.positiveInteger) {
            return page
        }
        let withoutQuery = path.prefix { $0 != "?" && $0 != "#" }
        return withoutQuery.firstMatch(of: listPagePattern).flatMap { HFRURL.positiveInteger($0.output.1) }
    }

    /// Target of a pager link: an obfuscated `md_cryptlink` class or an `href`, on the element or its first such
    /// descendant; nil for a disabled entry or a link that is not a forum path.
    static func linkTarget(of element: Element) -> String? {
        let candidates = [element] + element.descendants(matching: .contains("md_cryptlink"))
            + ((try? element.getElementsByTag("a").array()) ?? [])
        for candidate in candidates {
            if let classes = try? candidate.attr("class"), let decoded = ObfuscatedURL.decode(classAttribute: classes) {
                return HFRURL.forumRelativePath(decoded)
            }
            if candidate.tagName() == "a", candidate.hasAttr("href"), let href = try? candidate.attr("href") {
                return HFRURL.forumRelativePath(href)
            }
        }
        return nil
    }

    // MARK: - Implementation

    /// Children of `div.left` whose whole text is a page number, with that number.
    private static func pageEntries(in container: Element) -> [(element: Element, number: Int)] {
        container.children().array().compactMap { element in
            let text = TopicListParser.trimmed(element.rawText)
            return HFRURL.positiveInteger(text).map { (element, $0) }
        }
    }

    // `Regex` is not `Sendable` (its output type could hold non-Sendable captures). This literal captures
    // only a `Substring` and the compiled program is initialised atomically by the runtime, so sharing is safe.
    nonisolated(unsafe) private static let listPagePattern = /\/liste_sujet-([0-9]+)\.htm$/
}
