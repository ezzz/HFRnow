import Foundation
import Testing
@testable import HFRStorage

/// The per-account MPStorage sync record `mpstorage.<account key>` (ADR 0013 §7, LOT-130).
@Suite struct MPStorageSyncStateStoreTests {
    static let date = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func noRecordIsUnasked() {
        let store = MPStorageSyncStateStore(settings: InMemorySettingsStore())
        #expect(store.record(for: "Alice") == .unasked)
    }

    @Test func theKeyIsThePrefixAndTheFrozenAccountKey() {
        #expect(MPStorageSyncStateStore.key(for: "Al\u{200B}ice") == "mpstorage.alice")
        #expect(MPStorageSyncStateStore.key(for: "\u{200B}") == nil)
    }

    @Test(arguments: MPStorageSyncState.allCases)
    func aStateRoundTripsWithItsDate(_ state: MPStorageSyncState) {
        let store = MPStorageSyncStateStore(settings: InMemorySettingsStore())
        #expect(store.set(state, for: "Alice", at: Self.date))
        #expect(store.record(for: "alice") == MPStorageSyncRecord(state: state, decidedAt: Self.date))
    }

    @Test func theValueIsTheJSONOfTheADR() {
        let settings = InMemorySettingsStore()
        MPStorageSyncStateStore(settings: settings).set(.on, for: "Alice", at: Self.date)
        #expect(settings.rawValue(forKey: "mpstorage.alice") == .string(#"{"decidedAt":"2027-01-15T08:00:00Z","state":"on"}"#))
    }

    @Test func oneAccountsStateNeverAppliesToAnother() {
        let store = MPStorageSyncStateStore(settings: InMemorySettingsStore())
        store.set(.declined, for: "Alice", at: Self.date)
        #expect(store.record(for: "Bob") == .unasked)
    }

    @Test(arguments: [
        SettingRawValue.bool(true),
        .string("on"),
        .string(#"{"decidedAt":"2027-01-15T08:00:00Z","state":"paused"}"#)
    ])
    func aValueThisBuildCannotReadIsUnreadable(_ raw: SettingRawValue) {
        let settings = InMemorySettingsStore(["mpstorage.alice": raw])
        let store = MPStorageSyncStateStore(settings: settings)
        #expect(store.record(for: "Alice") == nil)
        // The legacy switch never overwrites it.
        #expect(store.applyLegacySwitch(.active, accounts: ["Alice"], at: Self.date).isEmpty)
        #expect(settings.rawValue(forKey: "mpstorage.alice") == raw)
    }

    @Test func anEmptyAccountKeyIsNeverWritten() {
        let settings = InMemorySettingsStore()
        #expect(!MPStorageSyncStateStore(settings: settings).set(.on, for: "\u{200B}", at: Self.date))
        #expect(settings.rawValue(forKey: "mpstorage.") == nil)
    }

    @Test func theLegacySwitchOnTurnsOnTheAccountsNotDecidedYet() {
        let store = MPStorageSyncStateStore(settings: InMemorySettingsStore())
        store.set(.declined, for: "Bob", at: Self.date)
        #expect(store.applyLegacySwitch(.active, accounts: ["Alice", "Bob"], at: Self.date) == ["Alice"])
        #expect(store.record(for: "Alice") == MPStorageSyncRecord(state: .on, decidedAt: Self.date))
        #expect(store.record(for: "Bob")?.state == .declined)
    }

    @Test(arguments: [LegacyMPStorageSwitch.inactive, .notRead])
    func theLegacySwitchOffOrUnreadChangesNothing(_ legacy: LegacyMPStorageSwitch) {
        let settings = InMemorySettingsStore()
        #expect(MPStorageSyncStateStore(settings: settings).applyLegacySwitch(legacy, accounts: ["Alice"], at: Self.date).isEmpty)
        #expect(settings.rawValue(forKey: "mpstorage.alice") == nil)
    }

    @Test func keysTooLongForICloudStayOnTheDevice() {
        let long = String(repeating: "a", count: SyncedListsStore.maximumKeyLength)
        #expect(MPStorageSyncStateStore.keys(for: ["Alice", long, ""]) == ["mpstorage.alice"])
    }

    // MARK: One switch per function (#859)

    @Test func everyFunctionIsOnByDefault() {
        let store = MPStorageSyncStateStore(settings: InMemorySettingsStore())
        store.set(.on, for: "Alice", at: Self.date)
        for function in MPStorageFunction.allCases {
            #expect(store.record(for: "Alice")?.isEnabled(function) == true)
        }
    }

    @Test func aFunctionOffIsStoredPerAccountAndKeepsTheStateAndDate() {
        let settings = InMemorySettingsStore()
        let store = MPStorageSyncStateStore(settings: settings)
        store.set(.on, for: "Alice", at: Self.date)
        #expect(store.setFunction(.mpFlags, enabled: false, for: "alice"))
        #expect(store.record(for: "Alice")?.isEnabled(.mpFlags) == false)
        #expect(store.record(for: "Alice")?.isEnabled(.bookmarks) == true)
        #expect(store.record(for: "Alice")?.state == .on)
        #expect(store.record(for: "Alice")?.decidedAt == Self.date)
        #expect(store.record(for: "Bob")?.isEnabled(.mpFlags) == true)
        #expect(settings.rawValue(forKey: "mpstorage.alice")
            == .string(#"{"decidedAt":"2027-01-15T08:00:00Z","disabled":["mpFlags"],"state":"on"}"#))
    }

    @Test func aStateChangeKeepsTheFunctionsOff() {
        let store = MPStorageSyncStateStore(settings: InMemorySettingsStore())
        store.set(.on, for: "Alice", at: Self.date)
        store.setFunction(.blacklist, enabled: false, for: "Alice")
        store.set(.off, for: "Alice", at: Self.date)
        store.set(.on, for: "Alice", at: Self.date)
        #expect(store.record(for: "Alice")?.isEnabled(.blacklist) == false)
    }

    @Test func switchingTheLastFunctionBackOnWritesTheOriginalShape() {
        let settings = InMemorySettingsStore()
        let store = MPStorageSyncStateStore(settings: settings)
        store.set(.on, for: "Alice", at: Self.date)
        store.setFunction(.bookmarks, enabled: false, for: "Alice")
        store.setFunction(.bookmarks, enabled: true, for: "Alice")
        #expect(settings.rawValue(forKey: "mpstorage.alice") == .string(#"{"decidedAt":"2027-01-15T08:00:00Z","state":"on"}"#))
    }

    @Test func aFunctionNameOfANewerBuildIsKept() {
        let settings = InMemorySettingsStore(
            ["mpstorage.alice": .string(#"{"decidedAt":"2027-01-15T08:00:00Z","disabled":["superFavs"],"state":"on"}"#)])
        let store = MPStorageSyncStateStore(settings: settings)
        store.setFunction(.mpFlags, enabled: false, for: "Alice")
        #expect(store.record(for: "Alice")?.disabled == ["mpFlags", "superFavs"])
    }

    @Test func aFunctionCannotBeSwitchedWhenTheRecordIsUnreadable() {
        let settings = InMemorySettingsStore(["mpstorage.alice": .bool(true)])
        #expect(!MPStorageSyncStateStore(settings: settings).setFunction(.mpFlags, enabled: false, for: "Alice"))
        #expect(settings.rawValue(forKey: "mpstorage.alice") == .bool(true))
    }
}
