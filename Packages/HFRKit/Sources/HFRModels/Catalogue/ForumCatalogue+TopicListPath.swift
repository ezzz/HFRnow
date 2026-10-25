extension ForumCatalogue {
    /// Relative path of a forum's topic list, built as the legacy `kCatTemplateURL` (`Constants.h:65`) did.
    ///
    /// Returns nil for private messages, which have their own list URL and are not built here, and for pages below 1.
    /// The sub-forum parameter stays empty, as in legacy.
    public static func topicListPath(categoryID: CategoryID, filter: TopicListFilter = .all, page: Int = 1) -> String? {
        guard case .forum(let number) = categoryID, page >= 1 else { return nil }
        return "/forum1.php?config=hfr.inc&cat=\(number)&page=\(page)&subcat=&owntopic=\(filter.rawValue)"
    }
}
