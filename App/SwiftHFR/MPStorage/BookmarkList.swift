import Foundation
import HFRModels

// Port of Classes/Bookmark.m (getUrl) and Classes/MPStorage.m (parseBookmarks, getBookmarkForPost:numreponse:) @ 87fe0d1c.
// Differences: a bookmark is identified by category, topic and message (legacy compared `numreponse` only); the date reads
// « à » (legacy's literal `'a'`). GAP-040.
/// The bookmarks of an MPStorage document as the list shows them, and where each one opens (LOT-132).
enum BookmarkList {
    /// The bookmarks of `document`'s writable entry, newest first (legacy `parseBookmarks`); undated ones last, in document
    /// order. A message another client listed twice shows once (the list's rows are identified by it; a deletion removes all).
    static func bookmarks(in document: MPStorageDocument?) -> [MPStorageBookmark] {
        guard let document, let index = document.writableEntryIndex else { return [] }
        let list = document.data[index].bookmarks?.list ?? []
        var seen = Set<String>()
        return sorted(list).filter { seen.insert($0.id).inserted }
    }

    private static func sorted(_ list: [MPStorageBookmark]) -> [MPStorageBookmark] {
        list.enumerated().sorted { lhs, rhs in
            switch (lhs.element.createdAt, rhs.element.createdAt) {
            case let (left?, right?) where left != right: left > right
            case (.some, nil): true
            case (nil, .some): false
            default: lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    /// Whether `document` already bookmarks the message `id` names (`MPStorageBookmark.id`).
    static func contains(_ id: String, in document: MPStorageDocument?) -> Bool {
        guard let document, let index = document.writableEntryIndex else { return false }
        return document.data[index].bookmarks?.list.contains { $0.id == id } ?? false
    }

    /// The row's title: the trimmed label, « Bookmark » when blank (`BookmarksPlusView.swift:139-142`).
    static func title(of bookmark: MPStorageBookmark) -> String {
        let label = bookmark.label.trimmingCharacters(in: .whitespacesAndNewlines)
        return label.isEmpty ? "Bookmark" : label
    }

    /// Legacy's link to the message (`Bookmark.m:17-19`): `forum2.php` naming the message, so HFR serves its page (R25).
    static func link(of bookmark: MPStorageBookmark) -> String {
        let category = bookmark.category.addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? ""
        let message = bookmark.numreponse
        return "/forum2.php?config=hfr.inc&cat=\(category)&post=\(bookmark.topic)&numreponse=\(message)#t\(message)"
    }

    /// Where the row opens: the message's page, at the message (bug #106); nil when the link does not route to a topic.
    static func target(of bookmark: MPStorageBookmark) -> ReaderTarget? {
        ReaderTarget(link: link(of: bookmark))
    }

    /// The row's date, « - » without one (`BookmarksPlusView.swift:151-154`).
    static func dateText(of bookmark: MPStorageBookmark, timeZone: TimeZone = .current) -> String {
        guard let date = bookmark.createdAt else { return "-" }
        // Built per call: `DateFormatter` is not `Sendable`, and a list holds a few hundred rows at most.
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_FR")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "dd/MM/yyyy 'à' HH:mm"
        return formatter.string(from: date)
    }
}
