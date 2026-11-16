extension ForumCatalogue {
    /// Relative path of a forum's topic list, built as the legacy `kCatTemplateURL` (`Constants.h:65`) did.
    ///
    /// Returns nil for private messages, which have their own list URL and are not built here, and for pages below 1.
    /// The sub-forum parameter stays empty, as in legacy, in the short form of the category list. With `subcategory` (a value
    /// below 1 counts as none) the query is the one `R603d` captured byte for byte, in its parameter order: only `cat`, `page`,
    /// `subcat` and `owntopic` vary. The short form with a filled `subcat` was never captured.
    public static func topicListPath(
        categoryID: CategoryID, subcategory: Int? = nil, filter: TopicListFilter = .all, page: Int = 1
    ) -> String? {
        guard case .forum(let number) = categoryID, page >= 1 else { return nil }
        guard let subcategory, subcategory >= 1 else {
            return "/forum1.php?config=hfr.inc&cat=\(number)&page=\(page)&subcat=&owntopic=\(filter.rawValue)"
        }
        return "/forum1.php?config=hfr.inc&cat=\(number)&page=\(page)&subcat=\(subcategory)&sondage=0&owntopic=\(filter.rawValue)"
            + "&trash=0&trash_post=0&moderation=0&new=0&nojs=0&subcatgroup=0"
    }
}
