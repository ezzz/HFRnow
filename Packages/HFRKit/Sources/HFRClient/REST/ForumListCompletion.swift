import Foundation
import HFRModels

/// Completes a home page's sub-forum list with the REST sub-categories (LOT-168).
///
/// The home page lists only some sub-forums of a category (Programmation 13 of 27 with the injection
/// table, HFR-PROTOCOL §6b); the REST list has
/// them all (`R285a`-`R285c`). The home page stays the primary source: its links, with their paths and their order
/// (injected entries included, `SubforumInjection`), are kept as they are. A REST row the page has no link for is added
/// as the REST link (a `subcat` path), right after the entry of the REST row before it, so the REST order decides only
/// where the added ones go. The two sources name a list differently (a slug path, a `subcat` number), so rows are matched
/// by title.
enum ForumListCompletion {
    /// `home` completed with the rows of `rest` it has no link for; `home` alone when `rest` is empty.
    static func complete(_ home: [ForumLink], with rest: [ForumLink]) -> [ForumLink] {
        var entries = home.map { Entry(link: $0, matched: false) }
        var anchor = -1
        for row in rest {
            let key = Self.key(row.title)
            if let index = entries.firstIndex(where: { !$0.matched && Self.key($0.link.title) == key }) {
                entries[index].matched = true
                anchor = index
            } else {
                anchor += 1
                entries.insert(Entry(link: row, matched: true), at: anchor)
            }
        }
        return entries.map(\.link)
    }

    /// A title as the two sources may spell it (« Ada » and « ADA », accents and spacing aside).
    static func key(_ title: String) -> String {
        title.trimmingCharacters(in: .whitespacesAndNewlines).folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private struct Entry {
        var link: ForumLink
        var matched: Bool
    }
}
