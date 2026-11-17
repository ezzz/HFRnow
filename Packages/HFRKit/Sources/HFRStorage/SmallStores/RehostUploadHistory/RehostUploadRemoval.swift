import Foundation

/// An upload removed from the history (#966): a tombstone, so the iCloud merge by id never brings the image back from
/// another device's copy (ADR 0013 Amendment 4).
public struct RehostUploadRemoval: Sendable, Hashable, Codable {
    /// The `RehostedImage.id` of the removed upload.
    public var id: String
    /// When it was removed; the newest removals are the ones kept.
    public var removedAt: Date

    /// Creates a removal.
    public init(id: String, removedAt: Date) {
        self.id = id
        self.removedAt = removedAt
    }
}
