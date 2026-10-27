import Foundation

/// Paging of a forum opened from its forum-relative link.
enum SubforumPath {
    private static var pattern: Regex<Substring> { /liste_sujet-\d+\.htm/ }

    /// `path` for `page`: `liste_sujet-1.htm` becomes `liste_sujet-<page>.htm`; nil when the path is not a forum list path
    /// or the page is below 1.
    static func page(_ page: Int, of path: String) -> String? {
        guard page >= 1, path.contains(pattern) else { return nil }
        return path.replacing(pattern, with: "liste_sujet-\(page).htm", maxReplacements: 1)
    }
}
