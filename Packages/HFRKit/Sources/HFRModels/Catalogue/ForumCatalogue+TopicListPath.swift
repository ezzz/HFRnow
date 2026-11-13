extension ForumCatalogue {
    /// Relative path of a forum's topic list, built as the legacy `kCatTemplateURL` (`Constants.h:65`) did.
    ///
    /// Returns nil for private messages, which have their own list URL and are not built here, and for pages below 1.
    /// The sub-forum parameter stays empty, as in legacy, unless `subcategory` names one (`R603d`: `subcat=<s>` filters that
    /// sub-forum in place); a value below 1 counts as none.
    public static func topicListPath(
        categoryID: CategoryID, subcategory: Int? = nil, filter: TopicListFilter = .all, page: Int = 1
    ) -> String? {
        guard case .forum(let number) = categoryID, page >= 1 else { return nil }
        let subcat = subcategory.flatMap { $0 >= 1 ? String($0) : nil } ?? ""
        return "/forum1.php?config=hfr.inc&cat=\(number)&page=\(page)&subcat=\(subcat)&owntopic=\(filter.rawValue)"
    }
}
