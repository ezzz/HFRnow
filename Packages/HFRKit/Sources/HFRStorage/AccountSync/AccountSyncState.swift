import Foundation

/// This device's side of the account sync (LOT-173): the switch, the dates it acted on and the per-account stamps.
/// Kept in its own device-only Keychain item, never in the synchronizable one. An absent state is off with nothing known;
/// one a later version wrote is refused and never written over (#1200 P3), since reading it as off would erase the switch
/// and the tombstones it honoured. Damaged bytes are refused too, until the user's explicit switch-off resets them.
public struct AccountSyncState: Sendable, Hashable, Codable {
    /// Whether this device shares its accounts.
    public var isOn = false
    /// While on: the date of the explicit switch-on this device holds (its own or adopted), the sharing's logical version.
    public var enabledAt: Date?
    /// The newest tombstone this device acted on (its own switch-off included).
    public var honouredDeletedAt: Date?
    /// While a bootstrap is provisional: the `enabledAt` of the envelope it imported.
    public var provisionalEnabledAt: Date?
    /// Account keys a provisional bootstrap lent this device; dropped if it switches off while provisional.
    public var imported: Set<String> = []
    /// Per account key: the dates of the account's last credentials change and last explicit login.
    public var stamps: [String: AccountStamp] = [:]
    /// Per account key: deletions made while on, shared with the other devices.
    public var removed: [String: Date] = [:]
    /// True once this device held accounts of its own (or imported some): it never bootstraps by itself again.
    public var hadLocalAccounts = false

    /// Version written today.
    static let currentVersion = 1

    /// Creates the state of a device that never shared its accounts.
    public init() {}

    /// Whether a switch-off now drops the imported accounts.
    public var isProvisional: Bool { provisionalEnabledAt != nil }

    private enum CodingKeys: String, CodingKey {
        case version, isOn, enabledAt, honouredDeletedAt, provisionalEnabledAt, imported, stamps, removed, hadLocalAccounts
    }

    /// Reads a state; a version this code does not know is refused (`DecodingError`): the caller refuses to act on it.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let version = try container.decode(Int.self, forKey: .version)
        guard version == Self.currentVersion else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: container, debugDescription: "unsupported version")
        }
        isOn = try container.decode(Bool.self, forKey: .isOn)
        enabledAt = try container.decodeIfPresent(Date.self, forKey: .enabledAt)
        honouredDeletedAt = try container.decodeIfPresent(Date.self, forKey: .honouredDeletedAt)
        provisionalEnabledAt = try container.decodeIfPresent(Date.self, forKey: .provisionalEnabledAt)
        imported = try container.decodeIfPresent(Set<String>.self, forKey: .imported) ?? []
        stamps = try container.decodeIfPresent([String: AccountStamp].self, forKey: .stamps) ?? [:]
        removed = try container.decodeIfPresent([String: Date].self, forKey: .removed) ?? [:]
        hadLocalAccounts = try container.decodeIfPresent(Bool.self, forKey: .hadLocalAccounts) ?? false
        // An "on" state without its version cannot push safely: read it as off.
        if isOn && enabledAt == nil { isOn = false }
    }

    /// Writes every field with the current version.
    public func encode(to encoder: any Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(Self.currentVersion, forKey: .version)
        try container.encode(isOn, forKey: .isOn)
        try container.encodeIfPresent(enabledAt, forKey: .enabledAt)
        try container.encodeIfPresent(honouredDeletedAt, forKey: .honouredDeletedAt)
        try container.encodeIfPresent(provisionalEnabledAt, forKey: .provisionalEnabledAt)
        try container.encode(imported.sorted(), forKey: .imported)
        try container.encode(stamps, forKey: .stamps)
        try container.encode(removed, forKey: .removed)
        try container.encode(hadLocalAccounts, forKey: .hadLocalAccounts)
    }

    /// Bytes for the state item, keys sorted.
    func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return try encoder.encode(self)
    }

    /// What a state item holds.
    enum Stored: Equatable {
        /// A state this version reads; off with nothing known when the item is absent.
        case readable(AccountSyncState)
        /// A state written by a later version: a `version` above this one's. Never reset (#1200 P3).
        case laterVersion
        /// Bytes no version writes as they are (not JSON, no integer `version`, or this version without its fields): only
        /// the user's explicit switch-off resets them (#1200 P3, option (b)).
        case damaged
    }

    /// The state stored in `data`, told apart as `Stored` says.
    static func decoded(from data: Data?) -> Stored {
        guard let data else { return .readable(AccountSyncState()) }
        if let state = try? JSONDecoder().decode(AccountSyncState.self, from: data) { return .readable(state) }
        struct Versioned: Decodable { let version: Int }
        if let versioned = try? JSONDecoder().decode(Versioned.self, from: data), versioned.version > currentVersion {
            return .laterVersion
        }
        return .damaged
    }
}

extension AccountSyncState {
    /// An "off" state that remembers the newest tombstone it honoured.
    init(honouredDeletedAt: Date?) {
        self.init()
        self.honouredDeletedAt = honouredDeletedAt
    }
}
