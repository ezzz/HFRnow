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

extension SyncedValue {
    /// A stable fingerprint of a stored list (64-bit FNV-1a of its bytes), kept on the device to tell a list changed here
    /// from the one last synced without keeping the list twice.
    var digest: String {
        let bytes: Data = switch self {
        case .data(let data): data
        default: Data(String(describing: self).utf8)
        }
        var hash: UInt64 = 0xcbf2_9ce4_8422_2325
        for byte in bytes {
            hash ^= UInt64(byte)
            hash &*= 0x0000_0100_0000_01b3
        }
        return String(hash, radix: 16)
    }
}
