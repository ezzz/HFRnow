/// One row of the forum catalogue: a forum path as HFR links it, and the `cat` id that path stands for.
public struct ForumCatalogueEntry: Sendable, Hashable {
    /// Forum path as the legacy app compared it, relative (`/hfr/...`) or, for one alias, absolute.
    public let path: String
    /// The `cat` value of the forum's topic list.
    public let categoryID: CategoryID

    /// Creates a catalogue row.
    public init(path: String, categoryID: CategoryID) {
        self.path = path
        self.categoryID = categoryID
    }
}
