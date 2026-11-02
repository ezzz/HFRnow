import Foundation
import Synchronization

/// The settings store of the app once iCloud sync is on (LOT-172, ADR 0013 §2-4): every read comes from the local store
/// (the `UserDefaults` mirror that `@AppStorage` also reads), every write goes to it, and the keys of `syncedKeys` are
/// also written to the iCloud key-value store, whose external changes `apply` (or `run`) copies back into the mirror.
///
/// The rules of ADR 0013 §3:
/// - **Server change**: the cloud value replaces the mirror's, key by key (last writer wins, as the store does).
/// - **Initial sync**: for each synced key, the cloud value wins; a key the cloud lacks is pushed from the mirror (a
///   first device, or values imported from legacy, LOT-067).
/// - **Account change** (another Apple ID, or signed out): the mirror's synced values are moved into a device-only
///   quarantine under the previous account's identity, never uploaded under the new one (values written while no
///   account was signed in belong to none and stay in the mirror); synced writes stay local and
///   nothing is applied or pushed until the new account's initial sync. Quarantined values come back only when their
///   account is active again (they then count as the mirror's values for the initial-sync rule), and are deleted after
///   `quarantineLifetime`.
/// - **Quota violation**: the local value is kept; the keys are reported in `quotaViolations`.
/// - **Schema version**: `schemaVersionKey` holds the newest format any device wrote; while it is above
///   `schemaVersion`, this build neither applies nor writes cloud values (it keeps working locally).
/// Device-scoped settings are never touched by any of this.
public final class SyncedSettingsStore: SettingsStore {
    /// The format of the synced values this build writes.
    public static let schemaVersion = 1
    /// The cloud key holding the newest schema version written (ADR 0013 appendix F).
    public static let schemaVersionKey = "schemaVersion"
    /// How long a quarantine is kept (ADR 0013 §3: 90 days).
    public static let quarantineLifetime: TimeInterval = 90 * 86_400

    private struct State {
        var quarantine: SmallStoreState<SyncQuarantineDocument>
        /// Entries the quarantine could not save: kept in memory rather than left in the mirror.
        var unsaved: [String: SyncQuarantineEntry] = [:]
        var identity: String?
        var waitsForInitialSync = false
        var quotaViolations: Set<String> = []
        var quarantineFailure: SmallStoreError?
    }

    private let local: any SettingsStore
    private let cloud: any SyncedKeyValueStore
    private let syncedKeys: Set<String>
    private let clock: @Sendable () -> Date
    private let state: Mutex<State>

    /// Creates the store over the local mirror, the cloud store and the quarantine file; nothing is exchanged until a
    /// write or a change. Quarantined values past their lifetime are deleted now.
    public init(
        local: any SettingsStore,
        cloud: any SyncedKeyValueStore,
        quarantine: any SmallStorePersistence<SyncQuarantineDocument>,
        syncedKeys: Set<String> = SettingKey.syncedKeys,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.local = local
        self.cloud = cloud
        self.syncedKeys = syncedKeys
        self.clock = clock
        state = Mutex(State(quarantine: SmallStoreState(persistence: quarantine), identity: cloud.accountIdentity()))
        state.withLock { Self.purge(&$0, now: clock()) }
    }

    // MARK: SettingsStore

    public func rawValue(forKey key: String) -> SettingRawValue? {
        local.rawValue(forKey: key)
    }

    public func setRawValue(_ value: SettingRawValue, forKey key: String) {
        local.setRawValue(value, forKey: key)
        guard syncedKeys.contains(key), canWriteCloud else { return }
        cloud.set(SyncedValue(value), forKey: key)
        stampSchema()
    }

    public func removeValue(forKey key: String) {
        local.removeValue(forKey: key)
        guard syncedKeys.contains(key), canWriteCloud else { return }
        cloud.removeValue(forKey: key)
    }

    // MARK: Changes

    /// Whether synced writes stay local until the active account's initial sync (after an account change).
    public var waitsForInitialSync: Bool {
        state.withLock { $0.waitsForInitialSync }
    }

    /// The keys the cloud refused for quota since the store was created; their local values are kept.
    public var quotaViolations: Set<String> {
        state.withLock { $0.quotaViolations }
    }

    /// Why the last quarantine could not be saved (its values are then kept in memory), or nil.
    public var quarantineFailure: SmallStoreError? {
        state.withLock { $0.quarantineFailure }
    }

    /// Applies the store's changes as they come; returns when the stream ends.
    public func run() async {
        for await change in cloud.changes() {
            apply(change)
        }
    }

    /// Applies one change of the cloud store (see the type's rules).
    public func apply(_ change: SyncedStoreChange) {
        switch change.reason {
        case .serverChange:
            guard !waitsForInitialSync, cloudSchemaIsReadable else { return }
            for key in change.keys where syncedKeys.contains(key) {
                copyCloudValue(forKey: key)
            }
        case .initialSync:
            initialSync()
        case .quotaViolation:
            state.withLock { $0.quotaViolations.formUnion(change.keys.filter(syncedKeys.contains)) }
        case .accountChange:
            accountChanged()
        }
    }

    // MARK: Internals

    private var canWriteCloud: Bool {
        !waitsForInitialSync && cloudSchemaIsReadable
    }

    private var cloudSchemaIsReadable: Bool {
        guard case .int(let version)? = cloud.value(forKey: Self.schemaVersionKey) else { return true }
        return version <= Self.schemaVersion
    }

    private func stampSchema() {
        if cloud.value(forKey: Self.schemaVersionKey) != .int(Self.schemaVersion) {
            cloud.set(.int(Self.schemaVersion), forKey: Self.schemaVersionKey)
        }
    }

    private func copyCloudValue(forKey key: String) {
        if let raw = cloud.value(forKey: key)?.settingRawValue {
            local.setRawValue(raw, forKey: key)
        } else if cloud.value(forKey: key) == nil {
            local.removeValue(forKey: key)
        }
    }

    private func initialSync() {
        let identity = cloud.accountIdentity()
        let restored = state.withLock { state -> [String: SyncedValue] in
            state.identity = identity
            state.waitsForInitialSync = false
            Self.purge(&state, now: clock())
            return Self.takeQuarantine(for: identity, from: &state)
        }
        for (key, value) in restored where local.rawValue(forKey: key) == nil {
            if let raw = value.settingRawValue { local.setRawValue(raw, forKey: key) }
        }
        guard cloudSchemaIsReadable else { return }
        var pushed = false
        for key in syncedKeys.sorted() {
            if cloud.value(forKey: key) != nil {
                copyCloudValue(forKey: key)
            } else if let raw = local.rawValue(forKey: key) {
                cloud.set(SyncedValue(raw), forKey: key)
                pushed = true
            }
        }
        if pushed { stampSchema() }
    }

    private func accountChanged() {
        let now = clock()
        let newIdentity = cloud.accountIdentity()
        // Values written while no Apple ID was signed in belong to none: they stay in the mirror, and the next initial
        // sync lets the cloud win and pushes the rest, as for a first device.
        let hadAccount = state.withLock { state -> Bool in
            guard state.identity == nil else { return true }
            state.identity = newIdentity
            state.waitsForInitialSync = true
            return false
        }
        guard hadAccount else { return }
        var values: [String: SyncedValue] = [:]
        for key in syncedKeys {
            if let raw = local.rawValue(forKey: key) { values[key] = SyncedValue(raw) }
        }
        state.withLock { state in
            let owner = state.identity ?? ""
            let entry = SyncQuarantineEntry(savedAt: now, values: values)
            do throws(SmallStoreError) {
                _ = try state.quarantine.mutate { document throws(SmallStoreError) in
                    document.entries[owner] = entry
                    return true
                }
                state.quarantineFailure = nil
            } catch {
                state.unsaved[owner] = entry
                state.quarantineFailure = error
            }
            state.identity = newIdentity
            state.waitsForInitialSync = true
            Self.purge(&state, now: now)
        }
        for key in syncedKeys { local.removeValue(forKey: key) }
    }

    /// Removes and returns the quarantined values of `identity`.
    private static func takeQuarantine(for identity: String?, from state: inout State) -> [String: SyncedValue] {
        guard let owner = identity else { return [:] }
        var values = state.unsaved.removeValue(forKey: owner)?.values ?? [:]
        let saved = state.quarantine.document()?.entries[owner]
        if let saved {
            values.merge(saved.values) { unsaved, _ in unsaved }
            _ = try? state.quarantine.mutate { document in document.entries.removeValue(forKey: owner) != nil }
        }
        return values
    }

    /// Deletes quarantined entries older than `quarantineLifetime`.
    private static func purge(_ state: inout State, now: Date) {
        let limit = now.addingTimeInterval(-quarantineLifetime)
        state.unsaved = state.unsaved.filter { $0.value.savedAt > limit }
        guard let entries = state.quarantine.document()?.entries, entries.values.contains(where: { $0.savedAt <= limit }) else { return }
        _ = try? state.quarantine.mutate { document in
            document.entries = document.entries.filter { $0.value.savedAt > limit }
            return true
        }
    }
}
