import Foundation

/// One successful smiley search remembered for suggestions.
public struct SmileySearchHistoryEntry: Sendable, Hashable, Codable {
    /// The search as first typed; later searches that differ only by case count towards it.
    public var text: String
    /// How many successful searches used it.
    public var count: Int
    /// When it was last searched.
    public var lastSearchedAt: Date

    /// Creates an entry.
    public init(text: String, count: Int, lastSearchedAt: Date) {
        self.text = text
        self.count = count
        self.lastSearchedAt = lastSearchedAt
    }
}
