import HFRModels
import SwiftSoup

/// Parses the private messages list (`GET /forum1.php?config=hfr.inc&cat=prive&page=N`, HFR-PROTOCOL R4).
///
/// The page is a topic list (LOT-022): rows, pager and title paths come from `TopicListParser`. This adds what only the
/// MP list has: the `[non lu]` marker (the *others* have not read, `span.red[title]`), the interlocutors and group threads.
/// Replaces `ObjCMPTopicsLoaderWorker` and the title-prefix reading of `MPListView.swift:12-36`; differences from legacy
/// are in `docs/lots/LOT-023-mp-list.md`.
public enum PrivateMessageListParser {
    /// Parses one page of the list.
    /// - Parameters:
    ///   - html: The page as served (UTF-8 text).
    ///   - pageURL: The URL the page was served from, as for `TopicListParser.parse`.
    /// - Throws: `.notAuthenticated` for the `.hop` message HFR serves to a logged-out request, `.maintenance` and
    ///   `.malformed` as `TopicListParser`; `.malformed` too when the page is a list of another category.
    ///   A `.notAuthenticated` on a page after the first is not proof of a lost session (the page may be past the end after a
    ///   deletion, never captured): callers confirm on page 1 before clearing a session.
    public static func parse(_ html: String, pageURL: String) throws(ListPageFailure) -> PrivateMessageListPage {
        let parsed = try TopicListParser.parseRows(html, pageURL: pageURL)
        // Whatever the URL, a message page in answer to the MP list is the login wall: an empty mailbox keeps its list body (R13c).
        if let notice = parsed.page.notice { throw .notAuthenticated(notice) }
        guard parsed.page.categoryID == .privateMessages else {
            throw .malformed("not the private messages list (category \(parsed.page.categoryID?.queryValue ?? "unknown"))")
        }
        return PrivateMessageListPage(
            threads: parsed.rows.map(thread(from:)),
            navigation: parsed.page.navigation,
            newMessagePath: parsed.page.newTopicPath
        )
    }

    // MARK: - Rows

    private static func thread(from row: ParsedTopicRow) -> PrivateMessageThread {
        let marker = row.element.firstDescendant(matching: .classToken("sujetCase3"))
            .flatMap { $0.descendants(matching: .classToken("red")).first { $0.tagName() == "span" } }
        var summary = row.summary
        if let marker {
            // The title cell reads "[non lu] <title>" (legacy kept it; MPListView stripped it by prefix).
            let markerText = TopicListParser.trimmed(marker.rawText)
            if summary.title.hasPrefix(markerText) {
                summary.title = TopicListParser.trimmed(String(summary.title.dropFirst(markerText.count)))
            }
        }
        let starterCell = row.element.firstDescendant(matching: .classToken("sujetCase6"))
        // A profile link is a one-to-one thread; without one, the span "Interlocuteurs multiples" names the others in its tooltip.
        let hasProfileLink = starterCell.map { !((try? $0.getElementsByTag("a").array()) ?? []).isEmpty } ?? false
        // A span without a tooltip is not taken for a group: a deleted interlocutor may print one (never captured, pending in the spec).
        let groupSpan = hasProfileLink ? nil : starterCell
            .flatMap { try? $0.getElementsByTag("span").first() }
            .flatMap { ((try? $0.attr("title")) ?? "").isEmpty ? nil : $0 }
        let interlocutors: [String]
        if let groupSpan {
            interlocutors = pseudos(in: (try? groupSpan.attr("title")) ?? "")
        } else {
            interlocutors = summary.starterOrInterlocutors.isEmpty ? [] : [summary.starterOrInterlocutors]
        }
        return PrivateMessageThread(
            summary: summary,
            unreadBy: marker.map { pseudos(afterColonIn: (try? $0.attr("title")) ?? "") } ?? [],
            isUnreadByOthers: marker != nil,
            interlocutors: interlocutors,
            isGroup: groupSpan != nil
        )
    }

    /// Names after the colon of "Ce message n'a pas été lu par : a, b": the sentence holds no other colon.
    private static func pseudos(afterColonIn text: String) -> [String] {
        guard let colon = text.firstIndex(of: ":") else { return [] }
        return pseudos(in: String(text[text.index(after: colon)...]))
    }

    /// Comma-separated pseudos, HFR joins them with ", " or ","; blanks dropped. A pseudo that itself holds a comma would split.
    private static func pseudos(in text: String) -> [String] {
        text.split(separator: ",").map { TopicListParser.trimmed(String($0)) }.filter { !$0.isEmpty }
    }
}
