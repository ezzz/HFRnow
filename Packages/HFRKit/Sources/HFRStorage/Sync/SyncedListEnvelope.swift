import Foundation

/// The cloud form of a whole list (ADR 0013 §3): `{"version":1,"items":[…]}`, JSON with sorted keys and dates in
/// seconds since 1970, stored as `SyncedValue.data` under one key.
struct SyncedListEnvelope<Item: Codable & Hashable>: Codable, Hashable {
    /// The format this code writes and reads.
    static var currentVersion: Int { 1 }

    var version: Int
    var items: [Item]

    init(items: [Item]) {
        version = Self.currentVersion
        self.items = items
    }

    /// The envelope as stored.
    var value: SyncedValue {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .secondsSince1970
        // Encoding plain Codable values into JSON cannot fail.
        return .data((try? encoder.encode(self)) ?? Data())
    }

    /// The envelope a stored value holds; nil for another type, another shape or a newer version.
    init?(_ value: SyncedValue) {
        guard case .data(let data) = value else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        guard let envelope = try? decoder.decode(Self.self, from: data),
              (1...Self.currentVersion).contains(envelope.version) else { return nil }
        self = envelope
    }
}
