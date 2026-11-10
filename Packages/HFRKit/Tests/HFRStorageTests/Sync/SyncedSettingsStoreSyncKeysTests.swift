import Foundation
import Testing
@testable import HFRStorage

/// Keys registered at run time (`syncKeys`, LOT-130): the per-account MPStorage records join the synced keys.
@Suite struct SyncedSettingsStoreSyncKeysTests {
    static let key = "mpstorage.alice"
    static let onValue = SettingRawValue.string(#"{"decidedAt":"2027-01-15T08:00:00Z","state":"on"}"#)
    static let offValue = SettingRawValue.string(#"{"decidedAt":"2027-01-16T08:00:00Z","state":"off"}"#)

    typealias Stores = (store: SyncedSettingsStore, local: InMemorySettingsStore)

    static func make(local: [String: SettingRawValue] = [:], cloud: InMemorySyncedKeyValueStore) -> Stores {
        let localStore = InMemorySettingsStore(local)
        let deviceState = InMemorySmallStorePersistence(SyncDeviceStateDocument(identityRecorded: true, knownIdentity: "account-1"))
        return (SyncedSettingsStore(local: localStore, cloud: cloud, deviceState: deviceState), localStore)
    }

    static func cloud(_ values: [String: SyncedValue] = [:]) -> InMemorySyncedKeyValueStore {
        InMemorySyncedKeyValueStore(values, identity: "account-1")
    }

    @Test func aKeyNotRegisteredStaysOnTheDevice() {
        let cloud = Self.cloud()
        let (store, _) = Self.make(cloud: cloud)
        store.setRawValue(Self.onValue, forKey: Self.key)
        #expect(cloud.value(forKey: Self.key) == nil)
    }

    @Test func aRegisteredKeyIsPushedWhenTheCloudHasNone() {
        let cloud = Self.cloud()
        let (store, _) = Self.make(local: [Self.key: Self.onValue], cloud: cloud)
        store.syncKeys([Self.key])
        #expect(cloud.value(forKey: Self.key) == SyncedValue(Self.onValue))
    }

    @Test func theCloudValueWinsAtRegistration() {
        let (store, local) = Self.make(local: [Self.key: Self.onValue], cloud: Self.cloud([Self.key: SyncedValue(Self.offValue)]))
        store.syncKeys([Self.key])
        #expect(local.rawValue(forKey: Self.key) == Self.offValue)
    }

    @Test func aRegisteredKeyFollowsWritesAndServerChanges() {
        let cloud = Self.cloud()
        let (store, local) = Self.make(cloud: cloud)
        store.syncKeys([Self.key])
        store.setRawValue(Self.onValue, forKey: Self.key)
        #expect(cloud.value(forKey: Self.key) == SyncedValue(Self.onValue))
        cloud.receive(SyncedStoreChange(reason: .serverChange, keys: [Self.key]), updates: [Self.key: SyncedValue(Self.offValue)])
        store.apply(SyncedStoreChange(reason: .serverChange, keys: [Self.key]))
        #expect(local.rawValue(forKey: Self.key) == Self.offValue)
    }

    @Test func registeringAgainLeavesTheMirrorAlone() {
        let cloud = Self.cloud()
        let (store, local) = Self.make(cloud: cloud)
        store.syncKeys([Self.key])
        // A cloud value the store has not been told about yet: a second registration must not apply it.
        cloud.set(SyncedValue(Self.offValue), forKey: Self.key)
        store.syncKeys([Self.key])
        #expect(local.rawValue(forKey: Self.key) == nil)
    }
}
