/// Pagination of a list page; defaults describe a single page, as the legacy parser did.
public struct PageNavigation: Sendable, Hashable, Codable {
    /// Page being shown (1-based).
    public var current: Int
    /// First page number of the pager.
    public var first: Int
    /// Last page number of the pager.
    public var last: Int
    /// Whether `last` is the real page count; false when it is only the last page the pager links to (a lower bound).
    ///
    /// The forum-list pager is a window (`1 … 10 20 … 100 200`), so a "last page" built from it is a fake total.
    public var isExact: Bool
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
        isExact: Bool = false,
        firstPath: String? = nil,
        lastPath: String? = nil,
        nextPath: String? = nil,
        previousPath: String? = nil
    ) {
        self.current = current
        self.first = first
        self.last = last
        self.isExact = isExact
        self.firstPath = firstPath
        self.lastPath = lastPath
        self.nextPath = nextPath
        self.previousPath = previousPath
    }

    private enum CodingKeys: String, CodingKey {
        case current, first, last, isExact, firstPath, lastPath, nextPath, previousPath
    }

    /// Decodes a navigation; a record written before `isExact` existed decodes as a lower bound, never as exact.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.current = try container.decode(Int.self, forKey: .current)
        self.first = try container.decode(Int.self, forKey: .first)
        self.last = try container.decode(Int.self, forKey: .last)
        self.isExact = try container.decodeIfPresent(Bool.self, forKey: .isExact) ?? false
        self.firstPath = try container.decodeIfPresent(String.self, forKey: .firstPath)
        self.lastPath = try container.decodeIfPresent(String.self, forKey: .lastPath)
        self.nextPath = try container.decodeIfPresent(String.self, forKey: .nextPath)
        self.previousPath = try container.decodeIfPresent(String.self, forKey: .previousPath)
    }
}
