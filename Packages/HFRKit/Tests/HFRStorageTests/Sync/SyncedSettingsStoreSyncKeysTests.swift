import Foundation
import Testing
@testable import HFRStorage

/// Keys registered at run time (`syncKeys`, LOT-130): the per-account MPStorage records join the synced keys.
@Suite struct SyncedSettingsStoreSyncKeysTests {
    static let key = "mpstorage.alice"
    static let on = SettingRawValue.string(#"{"decidedAt":"2027-01-15T08:00:00Z","state":"on"}"#)
    static let off = SettingRawValue.string(#"{"decidedAt":"2027-01-16T08:00:00Z","state":"off"}"#)

    static func make(
        local: [String: SettingRawValue] = [:], cloud: [String: SyncedValue] = [:]
    ) -> (SyncedSettingsStore, InMemorySettingsStore, InMemorySyncedKeyValueStore) {
        let localStore = InMemorySettingsStore(local)
        let cloudStore = InMemorySyncedKeyValueStore(cloud, identity: "account-1")
        let deviceState = InMemorySmallStorePersistence(SyncDeviceStateDocument(identityRecorded: true, knownIdentity: "account-1"))
        return (SyncedSettingsStore(local: localStore, cloud: cloudStore, deviceState: deviceState), localStore, cloudStore)
    }

    @Test func aKeyNotRegisteredStaysOnTheDevice() {
        let (store, _, cloud) = Self.make()
        store.setRawValue(Self.on, forKey: Self.key)
        #expect(cloud.value(forKey: Self.key) == nil)
    }

    @Test func aRegisteredKeyIsPushedWhenTheCloudHasNone() {
        let (store, _, cloud) = Self.make(local: [Self.key: Self.on])
        store.syncKeys([Self.key])
        #expect(cloud.value(forKey: Self.key) == SyncedValue(Self.on))
    }

    @Test func theCloudValueWinsAtRegistration() {
        let (store, local, _) = Self.make(local: [Self.key: Self.on], cloud: [Self.key: SyncedValue(Self.off)])
        store.syncKeys([Self.key])
        #expect(local.rawValue(forKey: Self.key) == Self.off)
    }

    @Test func aRegisteredKeyFollowsWritesAndServerChanges() {
        let (store, local, cloud) = Self.make()
        store.syncKeys([Self.key])
        store.setRawValue(Self.on, forKey: Self.key)
        #expect(cloud.value(forKey: Self.key) == SyncedValue(Self.on))
        cloud.receive(SyncedStoreChange(reason: .serverChange, keys: [Self.key]), updates: [Self.key: SyncedValue(Self.off)])
        store.apply(SyncedStoreChange(reason: .serverChange, keys: [Self.key]))
        #expect(local.rawValue(forKey: Self.key) == Self.off)
    }

    @Test func registeringAgainLeavesTheMirrorAlone() {
        let (store, local, cloud) = Self.make()
        store.syncKeys([Self.key])
        // A cloud value the store has not been told about yet: a second registration must not apply it.
        cloud.set(SyncedValue(Self.off), forKey: Self.key)
        store.syncKeys([Self.key])
        #expect(local.rawValue(forKey: Self.key) == nil)
    }
}
