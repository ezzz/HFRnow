import Foundation

/// A smiley the member added to the app's own favourites (not the forum-side favourites, which HFR serves).
public struct AppSmileyFavorite: Sendable, Hashable, Codable {
    /// Smiley code, e.g. `[:exemple]`, compared exactly as legacy did (`SmileyCache.m:398, 444-449`).
    public var code: String
    /// Image URL of the smiley.
    public var url: URL
    /// When it was added; the list is ordered by it, oldest first (LOT-004 quirk 22).
    public var addedAt: Date

    /// Creates a favourite.
    public init(code: String, url: URL, addedAt: Date) {
        self.code = code
        self.url = url
        self.addedAt = addedAt
    }
}
