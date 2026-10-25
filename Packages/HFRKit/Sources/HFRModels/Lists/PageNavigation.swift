/// Pagination of a list page; defaults describe a single page, as the legacy parser did.
public struct PageNavigation: Sendable, Hashable, Codable {
    /// Page being shown (1-based).
    public var current: Int
    /// First page number of the pager.
    public var first: Int
    /// Last page number of the pager.
    public var last: Int
    /// Path of the first page, when the pager links to it.
    public var firstPath: String?
    /// Path of the last page, when the pager links to it.
    public var lastPath: String?
    /// Path of the next page, when there is one.
    public var nextPath: String?
    /// Path of the previous page, when there is one.
    public var previousPath: String?

    /// Creates a pagination description.
    public init(
        current: Int = 1,
        first: Int = 1,
        last: Int = 1,
        firstPath: String? = nil,
        lastPath: String? = nil,
        nextPath: String? = nil,
        previousPath: String? = nil
    ) {
        self.current = current
        self.first = first
        self.last = last
        self.firstPath = firstPath
        self.lastPath = lastPath
        self.nextPath = nextPath
        self.previousPath = previousPath
    }
}
