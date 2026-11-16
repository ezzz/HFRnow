import Foundation

/// Reads and writes the per-account MPStorage sync records (ADR 0013 §7) in the app's settings store: the `UserDefaults`
/// mirror, which `SyncedSettingsStore` copies to iCloud once `keys(for:)` are registered with `syncKeys(_:)`.
///
/// The value is a JSON string `{"decidedAt":"<ISO 8601>","state":"<state>"}`, keys sorted, plus
/// `"disabled":["<function>",…]` only while a function is off (#859): absent or empty = every function on, an
/// unknown name is kept, it syncs with the state. A build without #859 ignores `disabled` and its master toggle
/// rewrites the record without it (ADR 0013 §7). A value this build cannot read (another shape, a state added by a
/// newer build) is **unreadable**: `record(for:)` answers nil, and nothing but an explicit `set` replaces it. A
/// `set` keeps the functions switched off (#859).
public struct MPStorageSyncStateStore: Sendable {
    /// The prefix of every record key.
    public static let keyPrefix = "mpstorage."

    private let settings: any SettingsStore

    /// Creates the store over `settings`.
    public init(settings: any SettingsStore) {
        self.settings = settings
    }

    /// The record key of `account` (`md_user` as the app stores it): `mpstorage.<account key>`, nil for an empty key.
    public static func key(for account: String) -> String? {
        let accountKey = AccountKey.make(account)
        return accountKey.isEmpty ? nil : keyPrefix + accountKey
    }

    /// The keys of `accounts` that fit an iCloud key (`SyncedListsStore.maximumKeyLength`), for `syncKeys(_:)`; a longer
    /// one stays on the device.
    public static func keys(for accounts: [String]) -> Set<String> {
        Set(accounts.compactMap(key(for:)).filter { $0.utf8.count <= SyncedListsStore.maximumKeyLength })
    }

    /// The account's record: `.unasked` when none is stored, nil when the stored value is unreadable.
    public func record(for account: String) -> MPStorageSyncRecord? {
        guard let key = Self.key(for: account) else { return .unasked }
        guard let raw = settings.rawValue(forKey: key) else { return .unasked }
        guard case .string(let text) = raw else { return nil }
        return try? Self.decoder.decode(MPStorageSyncRecord.self, from: Data(text.utf8))
    }

    /// Stores `state`, decided at `date`. Returns false, and writes nothing, for an empty account key.
    @discardableResult
    public func set(_ state: MPStorageSyncState, for account: String, at date: Date) -> Bool {
        guard let key = Self.key(for: account),
              let data = try? Self.encoder.encode(
                MPStorageSyncRecord(state: state, decidedAt: date, disabled: record(for: account)?.disabled)),
              let text = String(data: data, encoding: .utf8)
        else { return false }
        settings.setRawValue(.string(text), forKey: key)
        return true
    }

    /// Switches one function of the account on or off (#859), keeping its state and date. Returns false, and writes
    /// nothing, for an empty account key or a record this build cannot read.
    @discardableResult
    public func setFunction(_ function: MPStorageFunction, enabled: Bool, for account: String) -> Bool {
        guard let key = Self.key(for: account), let current = record(for: account),
              let data = try? Self.encoder.encode(current.setting(function, enabled: enabled)),
              let text = String(data: data, encoding: .utf8)
        else { return false }
        settings.setRawValue(.string(text), forKey: key)
        return true
    }

    /// Applies the legacy `mpstorage_active` read once by LOT-067: `.active` turns every listed account still `unasked`
    /// (no record) `on`, decided at `date`; `.inactive` and `.notRead` change nothing (`unasked` is the default).
    /// Returns the accounts switched on.
    @discardableResult
    public func applyLegacySwitch(_ legacy: LegacyMPStorageSwitch, accounts: [String], at date: Date) -> [String] {
        guard legacy == .active else { return [] }
        return accounts.filter { account in
            guard let key = Self.key(for: account), settings.rawValue(forKey: key) == nil else { return false }
            return set(.on, for: account, at: date)
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
