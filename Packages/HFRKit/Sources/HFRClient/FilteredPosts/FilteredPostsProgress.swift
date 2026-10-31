/// Where a filtering run stands after reading a page: legacy's "N posts | page X/Y" (`FavoritePostFilterService.swift:10-19`).
public struct FilteredPostsProgress: Sendable, Equatable {
    /// The page just read.
    public let page: Int
    /// The topic's last page, as that page shows it.
    public let maxPage: Int
    /// Messages kept so far in this batch.
    public let resultCount: Int
}
