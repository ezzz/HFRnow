import Foundation

/// This device's side of the account sync (LOT-173): the switch, the dates it acted on and the per-account stamps.
/// Kept in its own device-only Keychain item, never in the synchronizable one. An absent or unreadable state is off with
/// nothing known (fail closed).
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

    /// Reads a state; a version this code does not know is refused (`DecodingError`), and the caller reads it as off.
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

    /// The state stored in `data`; off with nothing known when absent or undecodable.
    static func decoded(from data: Data?) -> AccountSyncState {
        guard let data, let state = try? JSONDecoder().decode(AccountSyncState.self, from: data) else { return AccountSyncState() }
        return state
    }
}
