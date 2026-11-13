import Foundation

/// The category and numeric `subcat` of a sub-forum, which `forum1.php` needs to filter it (`R603d`).
///
/// The home page links a sub-forum by path only. The sub-forum's own list page names the numbers in its "new topic" link
/// (`/message.php?config=hfr.inc&cat=<c>&sond=0&p=1&subcat=<s>&dest=&subcatgroup=0`, `R06`, `R603d`), logged out or in; a
/// category's page links `/hfr/<cat>/nouveau_sujet.htm` instead, which carries none (`R09`).
public struct SubforumTarget: Sendable, Hashable {
    public let category: CategoryID
    public let subcategory: Int

    public init(category: CategoryID, subcategory: Int) {
        self.category = category
        self.subcategory = subcategory
    }

    /// Reads the target from a list page's `newTopicPath`; nil when the link names no category or no positive `subcat`.
    public init?(newTopicPath: String?) {
        guard let newTopicPath, let items = URLComponents(string: newTopicPath)?.queryItems else { return nil }
        func number(_ name: String) -> Int? {
            items.first { $0.name == name }?.value.flatMap { Int($0) }.flatMap { $0 >= 1 ? $0 : nil }
        }
        guard let category = number("cat"), let subcategory = number("subcat") else { return nil }
        self.init(category: .forum(category), subcategory: subcategory)
    }
}
