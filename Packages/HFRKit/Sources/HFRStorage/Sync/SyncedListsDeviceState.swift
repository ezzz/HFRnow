/// What the list sync keeps on this device only (LOT-172 part 2, ADR 0013 Amendment 2): the Apple ID the local lists
/// belong to, the stores that could not be set aside at an Apple ID change, and the lists set aside.
public struct SyncedListsDeviceState: SmallStoreDocument {
    /// Format version written by this code.
    public static let currentVersion = 1
    /// A document of a device that never ran the list sync.
    public static var empty: Self { Self() }

    /// Format version.
    public var version: Int
    /// The identity (`SyncedKeyValueStore.accountIdentity()`) of the Apple ID the local lists belong to: the last one
    /// signed in, nil before the first.
    public var owner: String?
    /// Stores that could not be read at an Apple ID change, by `SyncedListsStore` slot prefix, with the identity whose
    /// lists they still hold.
    public var stale: [String: String]
    /// Lists set aside, by the identity of the Apple ID they belong to; values by slot, each an envelope (`.data`).
    public var quarantine: [String: SyncQuarantineEntry]
    /// Per cloud key, the digest of the list last applied or pushed for `owner`: a local list that differs was changed
    /// on this device since, for example while signed out.
    public var synced: [String: String]

    /// Creates a document.
    public init(
        version: Int = Self.currentVersion,
        owner: String? = nil,
        stale: [String: String] = [:],
        quarantine: [String: SyncQuarantineEntry] = [:],
        synced: [String: String] = [:]
    ) {
        self.version = version
        self.owner = owner
        self.stale = stale
        self.quarantine = quarantine
        self.synced = synced
    }

    private enum CodingKeys: String, CodingKey {
        case version, owner, stale, quarantine, synced
    }

    /// Decodes a document; a field a later version of this type adds reads as its default when missing.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        version = try container.decode(Int.self, forKey: .version)
        owner = try container.decodeIfPresent(String.self, forKey: .owner)
        stale = try container.decodeIfPresent([String: String].self, forKey: .stale) ?? [:]
        quarantine = try container.decodeIfPresent([String: SyncQuarantineEntry].self, forKey: .quarantine) ?? [:]
        synced = try container.decodeIfPresent([String: String].self, forKey: .synced) ?? [:]
    }
}
