/// The topic and page read from a canonical topic URL `/hfr/<cat>/<slug>-sujet_<topic>_<page>.htm` (HFR-PROTOCOL R5).
public struct CanonicalTopicPath: Sendable, Hashable {
    /// Topic number inside its category (the `post` query parameter of `forum2.php`).
    public var topic: Int
    /// One-based page number.
    public var page: Int

    /// Creates a canonical topic location.
    public init(topic: Int, page: Int) {
        self.topic = topic
        self.page = page
    }
}
