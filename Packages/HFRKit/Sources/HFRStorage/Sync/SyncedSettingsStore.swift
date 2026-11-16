import Foundation
import Synchronization

/// The settings store of the app once iCloud sync is on (LOT-172, ADR 0013 §2-4): every read comes from the local store
/// (the `UserDefaults` mirror that `@AppStorage` also reads), every write goes to it, and the keys of `syncedKeys` are
/// also written to the iCloud key-value store, whose changes `apply` (or `run`) copies back into the mirror.
///
/// The rules of ADR 0013 §3:
/// - **Server change**: the cloud value replaces the mirror's, key by key (last writer wins, as the store does).
/// - **Initial sync**: for each synced key, the cloud value wins; a key the cloud lacks is pushed from the mirror (a
///   first device, or values imported from legacy, LOT-067).
/// - **First launch**: the account is recorded and the initial-sync rule runs (ADR 0013 §5 step 2: device values first,
///   then the cloud).
/// - **Account change** (another Apple ID, or signed out), seen as it happens or, when it happened while the app was
///   not running, at the next launch (the last account seen is kept on the device): the mirror's synced values are
///   moved into a device-only quarantine under the previous account, so they are never uploaded under the new one; the
///   new account's own quarantine, if any, comes back; then the initial-sync rule applies to the store's content, which
///   the system has already replaced. Values written while no account was signed in belong to none and stay. A
///   quarantine is deleted after `quarantineLifetime`.
/// - **Quota violation**: the local value is kept; the keys are reported in `quotaViolations`.
/// - **Schema version**: `schemaVersionKey` holds the newest format any device wrote; while it is above
///   `schemaVersion`, this build neither applies nor writes cloud values (it keeps working locally).
///
/// Each write and each change runs as one critical section, so a write and a change never interleave. The local
/// store must not call back into this store synchronously (a `UserDefaults` observer writing a setting). Device-scoped
/// settings are never touched by any of this.
public final class SyncedSettingsStore: SettingsStore {
    /// The format of the synced values this build writes.
    public static let schemaVersion = 1
    /// The cloud key holding the newest schema version written (ADR 0013 appendix F).
    public static let schemaVersionKey = "schemaVersion"
    /// How long a quarantine is kept (ADR 0013 §3: 90 days).
    public static let quarantineLifetime: TimeInterval = 90 * 86_400

    private struct State {
        var device: SmallStoreState<SyncDeviceStateDocument>
        /// Quarantine entries the device file could not save: kept in memory rather than left in the mirror.
        var unsaved: [String: SyncQuarantineEntry] = [:]
        var identity: String?
        var quotaViolations: Set<String> = []
        var deviceStateFailure: SmallStoreError?
        /// The keys copied to iCloud: `SettingKey.syncedKeys` and the keys `syncKeys(_:)` added since.
        var syncedKeys: Set<String>
    }

    private let local: any SettingsStore
    private let cloud: any SyncedKeyValueStore
    private let clock: @Sendable () -> Date
    private let state: Mutex<State>

    /// Creates the store over the local mirror, the cloud store and the device-only state file. An account change made
    /// while the app was not running is handled now; quarantined values past their lifetime are deleted.
    public init(
        local: any SettingsStore,
        cloud: any SyncedKeyValueStore,
        deviceState: any SmallStorePersistence<SyncDeviceStateDocument>,
        syncedKeys: Set<String> = SettingKey.syncedKeys,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.local = local
        self.cloud = cloud
        self.clock = clock
        state = Mutex(State(device: SmallStoreState(persistence: deviceState), syncedKeys: syncedKeys))
        state.withLock { state in
            purge(&state)
            guard let document = state.device.document(), document.identityRecorded else {
                // A first launch: the values already on the device (defaults set, a legacy import) meet the cloud's,
                // as at an initial sync (ADR 0013 §5 step 2).
                state.identity = cloud.accountIdentity()
                record(&state)
                merge(state.syncedKeys)
                return
            }
            state.identity = document.knownIdentity
            if !cloud.isCurrentAccount(document.knownIdentity) { accountChanged(&state) }
        }
    }

    // MARK: SettingsStore

    public func rawValue(forKey key: String) -> SettingRawValue? {
        local.rawValue(forKey: key)
    }

    public func setRawValue(_ value: SettingRawValue, forKey key: String) {
        state.withLock { state in
            local.setRawValue(value, forKey: key)
            guard state.syncedKeys.contains(key), cloudSchemaIsReadable else { return }
            cloud.set(SyncedValue(value), forKey: key)
            stampSchema()
        }
    }

    public func removeValue(forKey key: String) {
        state.withLock { state in
            local.removeValue(forKey: key)
            guard state.syncedKeys.contains(key), cloudSchemaIsReadable else { return }
            cloud.removeValue(forKey: key)
        }
    }

    /// Copies `keys` to iCloud from now on, besides the catalogue's synced keys: the per-account keys of LOT-130
    /// (`MPStorageSyncStateStore.keys(for:)`), whose accounts come and go at run time. The keys not synced yet get the
    /// initial-sync rule at once: the cloud value wins, else the mirror's is pushed. Keys already synced are left alone.
    public func syncKeys(_ keys: Set<String>) {
        state.withLock { state in
            let added = keys.subtracting(state.syncedKeys)
            guard !added.isEmpty else { return }
            state.syncedKeys.formUnion(added)
            merge(added)
        }
    }

    // MARK: Changes

    /// The keys the cloud refused for quota since the store was created; their local values are kept.
    public var quotaViolations: Set<String> {
        state.withLock { $0.quotaViolations }
    }

    /// Why the device state file could not be read or written, or nil. Quarantined values are then kept in memory.
    public var deviceStateFailure: SmallStoreError? {
        state.withLock { $0.deviceStateFailure }
    }

    /// Applies the store's changes as they come; returns when the stream ends.
    public func run() async {
        for await change in cloud.changes() {
            apply(change)
        }
    }

    /// Applies one change of the cloud store (see the type's rules).
    public func apply(_ change: SyncedStoreChange) {
        state.withLock { state in
            switch change.reason {
            case .serverChange:
                guard cloudSchemaIsReadable else { return }
                for key in change.keys where state.syncedKeys.contains(key) {
                    copyCloudValue(forKey: key)
                }
            case .initialSync:
                purge(&state)
                merge(state.syncedKeys)
            case .quotaViolation:
                state.quotaViolations.formUnion(change.keys.filter(state.syncedKeys.contains))
            case .accountChange:
                accountChanged(&state)
            }
        }
    }

    // MARK: Internals (called inside the critical section)

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
        switch cloud.value(forKey: key) {
        case .none: local.removeValue(forKey: key)
        case .some(let value): if let raw = value.settingRawValue { local.setRawValue(raw, forKey: key) }
        }
    }

    /// The initial-sync rule over `keys`: the cloud wins where it has a value, the mirror's value is pushed where it has none.
    private func merge(_ keys: Set<String>) {
        guard cloudSchemaIsReadable else { return }
        var pushed = false
        for key in keys.sorted() {
            if cloud.value(forKey: key) != nil {
                copyCloudValue(forKey: key)
            } else if let raw = local.rawValue(forKey: key) {
                cloud.set(SyncedValue(raw), forKey: key)
                pushed = true
            }
        }
        if pushed { stampSchema() }
    }

    private func accountChanged(_ state: inout State) {
        let previous = state.identity
        let current = cloud.accountIdentity()
        if let previous, !cloud.isCurrentAccount(previous) {
            var values: [String: SyncedValue] = [:]
            for key in state.syncedKeys {
                if let raw = local.rawValue(forKey: key) { values[key] = SyncedValue(raw) }
                local.removeValue(forKey: key)
            }
            quarantine(values, for: previous, in: &state)
        }
        for (key, value) in takeQuarantine(for: current, from: &state) where local.rawValue(forKey: key) == nil {
            if let raw = value.settingRawValue { local.setRawValue(raw, forKey: key) }
        }
        state.identity = current
        record(&state)
        purge(&state)
        merge(state.syncedKeys)
    }

    private func quarantine(_ values: [String: SyncedValue], for owner: String, in state: inout State) {
        let entry = SyncQuarantineEntry(savedAt: clock(), values: values)
        do throws(SmallStoreError) {
            _ = try state.device.mutate { document throws(SmallStoreError) in
                document.quarantine[owner] = entry
                return true
            }
        } catch {
            state.unsaved[owner] = entry
            state.deviceStateFailure = error
        }
    }

    /// Removes and returns the quarantined values of the account `identity` (none for no account).
    private func takeQuarantine(for identity: String?, from state: inout State) -> [String: SyncedValue] {
        guard identity != nil else { return [:] }
        var values: [String: SyncedValue] = [:]
        for owner in state.unsaved.keys.sorted() where cloud.isCurrentAccount(owner) {
            values.merge(state.unsaved.removeValue(forKey: owner)?.values ?? [:]) { kept, _ in kept }
        }
        let saved = (state.device.document()?.quarantine ?? [:]).filter { cloud.isCurrentAccount($0.key) }
        guard !saved.isEmpty else { return values }
        for entry in saved.values { values.merge(entry.values) { kept, _ in kept } }
        _ = try? state.device.mutate { document throws(SmallStoreError) in
            for owner in saved.keys { document.quarantine.removeValue(forKey: owner) }
            return true
        }
        return values
    }

    /// Keeps the identity just seen, so the next launch can tell whether the account changed meanwhile.
    private func record(_ state: inout State) {
        let identity = state.identity
        do throws(SmallStoreError) {
            _ = try state.device.mutate { document throws(SmallStoreError) in
                guard !document.identityRecorded || document.knownIdentity != identity else { return false }
                document.identityRecorded = true
                document.knownIdentity = identity
                return true
            }
        } catch {
            state.deviceStateFailure = error
        }
    }

    /// Deletes quarantined entries older than `quarantineLifetime`.
    private func purge(_ state: inout State) {
        let limit = clock().addingTimeInterval(-Self.quarantineLifetime)
        state.unsaved = state.unsaved.filter { $0.value.savedAt > limit }
        guard let quarantine = state.device.document()?.quarantine, quarantine.values.contains(where: { $0.savedAt <= limit })
        else { return }
        _ = try? state.device.mutate { document throws(SmallStoreError) in
            document.quarantine = document.quarantine.filter { $0.value.savedAt > limit }
            return true
        }
    }
}
