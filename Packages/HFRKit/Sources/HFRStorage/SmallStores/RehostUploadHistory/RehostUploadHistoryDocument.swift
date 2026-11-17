import Foundation
import HFRModels

/// What the upload history persists: device-wide, personal data (ADR 0013 §1). With iCloud on, the 100 newest uploads
/// and the newest removals also follow the Apple ID through `SyncedListsStore` (ADR 0013 Amendment 4, #966).
public struct RehostUploadHistoryDocument: SmallStoreDocument {
    /// Format version written by this code.
    public static let currentVersion = 1
    /// The number of removals kept, the newest: as many as the uploads the iCloud copy holds (`SyncedListsStore`). A
    /// device that merges only after more removals than this were made elsewhere forgets the oldest ones, and can bring
    /// those uploads back (ADR 0013 Amendment 4, accepted limit).
    public static let removalsLimit = 100
    /// An empty history.
    public static var empty: Self { Self() }

    /// Format version.
    public var version: Int
    /// The uploaded images, the last one added first.
    public var images: [RehostedImage]
    /// The newest removals, newest first (#966); a build before it neither reads nor writes them.
    public var removals: [RehostUploadRemoval]

    /// Creates a document.
    public init(version: Int = Self.currentVersion, images: [RehostedImage] = [], removals: [RehostUploadRemoval] = []) {
        self.version = version
        self.images = images
        self.removals = removals
    }

    private enum CodingKeys: String, CodingKey {
        case version, images, removals
    }

    /// Decodes a document; `removals`, added by #966 without a version change, reads as empty when missing.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        images = try container.decode([RehostedImage].self, forKey: .images)
        removals = try container.decodeIfPresent([RehostUploadRemoval].self, forKey: .removals) ?? []
    }

    /// Encodes a document; an empty `removals` is left out, so a history without removals is written as before #966.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(version, forKey: .version)
        try container.encode(images, forKey: .images)
        if !removals.isEmpty { try container.encode(removals, forKey: .removals) }
    }

    /// The document once another copy's uploads and removals are merged in (#966): the union by `RehostedImage.id`,
    /// every removed id left out, the removals of both sides kept (the newest date of an id), newest first, capped to
    /// `removalsLimit`. Order: unchanged when nothing comes from `images`, else `newestFirst`.
    func merging(images incoming: [RehostedImage], removals incomingRemovals: [RehostUploadRemoval]) -> Self {
        var newest: [String: Date] = [:]
        for removal in removals + incomingRemovals {
            newest[removal.id] = max(newest[removal.id] ?? removal.removedAt, removal.removedAt)
        }
        var merged = self
        merged.removals = newest.map { RehostUploadRemoval(id: $0.key, removedAt: $0.value) }
            .sorted { ($0.removedAt, $1.id) > ($1.removedAt, $0.id) }
        merged.removals = Array(merged.removals.prefix(Self.removalsLimit))
        merged.images.removeAll { newest[$0.id] != nil }
        var known = Set(merged.images.map(\.id))
        let added = incoming.filter { newest[$0.id] == nil && known.insert($0.id).inserted }
        if !added.isEmpty { merged.images = Self.newestFirst(merged.images + added) }
        return merged
    }

    /// Uploads by date, newest first, equal dates by id: every device orders the same uploads the same way, so their
    /// cloud copies compare equal.
    static func newestFirst(_ images: [RehostedImage]) -> [RehostedImage] {
        images.sorted { lhs, rhs in
            lhs.uploadedAt != rhs.uploadedAt ? lhs.uploadedAt > rhs.uploadedAt : lhs.id < rhs.id
        }
    }
}
