import Foundation
import HFRModels

/// The cloud form of the upload history (#966, ADR 0013 Amendment 4): `{"version":1,"items":[…],"removals":[…]}`, JSON
/// with sorted keys, stored as `SyncedValue.data` under `SyncedListsStore.rehostHistoryKey`. The device's whole history
/// uses the same form in the quarantine of an Apple ID change.
///
/// Dates are `JSONEncoder`'s default (seconds since 2001), as in the device file (LOT-064): seconds since 1970 does not
/// read back the same `Date`, so a copy would never equal the device's own (the merge itself goes by id).
struct RehostHistoryEnvelope: Codable, Hashable {
    /// The format this code writes and reads.
    static let currentVersion = 1

    var version: Int
    var items: [RehostedImage]
    var removals: [RehostUploadRemoval]

    /// The cloud copy of a history: the `limit` newest uploads and every removal the document keeps.
    init(_ document: RehostUploadHistoryDocument, limit: Int) {
        version = Self.currentVersion
        items = Array(RehostUploadHistoryDocument.newestFirst(document.images).prefix(limit))
        removals = document.removals
    }

    /// The whole history, for the quarantine.
    init(_ document: RehostUploadHistoryDocument) {
        self.init(document, limit: .max)
    }

    private enum CodingKeys: String, CodingKey {
        case version, items, removals
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        items = try container.decode([RehostedImage].self, forKey: .items)
        removals = try container.decodeIfPresent([RehostUploadRemoval].self, forKey: .removals) ?? []
    }

    /// The envelope as stored.
    var value: SyncedValue {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        // Encoding plain Codable values into JSON cannot fail.
        return .data((try? encoder.encode(self)) ?? Data())
    }

    /// The envelope a stored value holds; nil for another type, another shape or a newer version, which this build
    /// never applies nor overwrites.
    init?(_ value: SyncedValue) {
        guard case .data(let data) = value,
              let envelope = try? JSONDecoder().decode(Self.self, from: data),
              (1...Self.currentVersion).contains(envelope.version) else { return nil }
        self = envelope
    }

    /// The history it holds, as the store keeps one.
    var document: RehostUploadHistoryDocument {
        RehostUploadHistoryDocument(images: items, removals: removals)
    }

    /// What two copies must share to need no push: the uploads by id, in order, and the removals. Dates are compared
    /// through the ids and the removals' own values, never through another encoding of the same content.
    var signature: [String] {
        items.map(\.id) + ["|"] + removals.map { "\($0.id)@\($0.removedAt.timeIntervalSinceReferenceDate)" }
    }
}
