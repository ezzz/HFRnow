import Foundation

/// A dated deletion marker kept in a section's `tombstones` array (`{"id":s,"deleteDate":ms}`), an addition to v0.1
/// that readers ignore. It lets a merge tell "deleted here" from "added there" when no common base is known.
public struct MPStorageTombstone: Sendable, Hashable, Codable {
    /// Merge key of the deleted item (see `MPStorageItem.storageKey`).
    public var id: String
    /// When the item was deleted.
    public var deletedAt: Date
    /// Keys written by other clients, kept so a rewrite does not drop them.
    public var extra: [String: JSONValue]

    /// How long a tombstone is kept, in seconds (90 days): longer than a device usually stays offline.
    public static let retention: TimeInterval = 90 * 86_400
    /// Most tombstones kept per section, so they cost at most a few KiB of the 64 KiB cap.
    public static let maximumPerSection = 50

    private static let knownKeys: Set<String> = ["id", "deleteDate"]

    /// Creates a tombstone.
    public init(id: String, deletedAt: Date, extra: [String: JSONValue] = [:]) {
        self.id = id
        self.deletedAt = deletedAt
        self.extra = extra
    }

    /// Decodes a tombstone; `id` and `deleteDate` are required.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicKey.self)
        guard let id = try container.decodeLenientStringIfPresent(forKey: DynamicKey("id")) else {
            throw DecodingError.keyNotFound(DynamicKey("id"), .init(codingPath: decoder.codingPath, debugDescription: "No id"))
        }
        guard let deletedAt = try container.decodeMillisecondDateIfPresent(forKey: DynamicKey("deleteDate")) else {
            let context = DecodingError.Context(codingPath: decoder.codingPath, debugDescription: "No deleteDate")
            throw DecodingError.keyNotFound(DynamicKey("deleteDate"), context)
        }
        self.id = id
        self.deletedAt = deletedAt
        extra = try container.decodeRemainingKeys(excluding: Self.knownKeys)
    }

    /// Encodes with a millisecond date and the preserved keys.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: DynamicKey.self)
        try container.encode(id, forKey: DynamicKey("id"))
        try container.encodeMilliseconds(deletedAt, forKey: DynamicKey("deleteDate"))
        try container.encodeRemainingKeys(extra, excluding: Self.knownKeys)
    }
}
