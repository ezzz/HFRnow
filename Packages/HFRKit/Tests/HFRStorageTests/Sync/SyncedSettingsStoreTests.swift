import Foundation
import Synchronization
import Testing
@testable import HFRStorage

/// The rules of ADR 0013 §3-4 on the in-memory store (LOT-172).
@Suite struct SyncedSettingsStoreTests {
    private static let synced = "display_sig"
    private static let other = "vos_sujets"
    private static let device = "compact_mode"
    private static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)

    /// A settable clock.
    final class Clock: Sendable {
        private let current = Mutex(SyncedSettingsStoreTests.start)
        var now: Date { current.withLock { $0 } }
        func advance(days: Double) { current.withLock { $0 = $0.addingTimeInterval(days * 86_400) } }
    }

    struct Fixture {
        let store: SyncedSettingsStore
        let local: InMemorySettingsStore
        let cloud: InMemorySyncedKeyValueStore
        let deviceState: InMemorySmallStorePersistence<SyncDeviceStateDocument>
        let clock: Clock

        /// The store the app would build at its next launch, over the same local store, cloud and device file.
        func relaunched() -> SyncedSettingsStore {
            SyncedSettingsStore(local: local, cloud: cloud, deviceState: deviceState, clock: { clock.now })
        }

        /// Plays an account change: the system replaces the store's content, then the store is told.
        func switchAccount(to identity: String?, cloudValues: [String: SyncedValue?] = [:]) {
            cloud.receive(SyncedStoreChange(reason: .accountChange), updates: cloudValues, identity: .some(identity))
            store.apply(SyncedStoreChange(reason: .accountChange))
        }
    }

    private static func make(
        local: [String: SettingRawValue] = [:],
        cloud: [String: SyncedValue] = [:],
        identity: String? = "account-1",
        deviceState: InMemorySmallStorePersistence<SyncDeviceStateDocument>? = nil
    ) -> Fixture {
        // A device that already ran the store for this account, unless the test gives another state.
        let deviceState = deviceState
            ?? InMemorySmallStorePersistence(SyncDeviceStateDocument(identityRecorded: true, knownIdentity: identity))
        let localStore = InMemorySettingsStore(local)
        let cloudStore = InMemorySyncedKeyValueStore(cloud, identity: identity)
        let clock = Clock()
        let store = SyncedSettingsStore(local: localStore, cloud: cloudStore, deviceState: deviceState, clock: { clock.now })
        return Fixture(store: store, local: localStore, cloud: cloudStore, deviceState: deviceState, clock: clock)
    }

    @Test func aSyncedWriteGoesToBothAndStampsTheSchemaADeviceWriteStaysLocal() {
        let fixture = Self.make()
        fixture.store.setRawValue(.string("yes"), forKey: Self.synced)
        fixture.store.setRawValue(.bool(true), forKey: Self.device)
        #expect(fixture.local.rawValue(forKey: Self.synced) == .string("yes"))
        #expect(fixture.cloud.value(forKey: Self.synced) == .string("yes"))
        #expect(fixture.cloud.value(forKey: SyncedSettingsStore.schemaVersionKey) == .int(SyncedSettingsStore.schemaVersion))
        #expect(fixture.cloud.value(forKey: Self.device) == nil)
        fixture.store.removeValue(forKey: Self.synced)
        #expect(fixture.cloud.value(forKey: Self.synced) == nil)
        #expect(fixture.local.rawValue(forKey: Self.synced) == nil)
    }

    @Test func readsComeFromTheMirrorOnly() {
        let fixture = Self.make(local: [Self.synced: .string("no")], cloud: [Self.synced: .string("yes")])
        #expect(fixture.store.rawValue(forKey: Self.synced) == .string("no"))
        #expect(fixture.store.value(for: SettingKey.displaySignatures) == false)
    }

    @Test func aServerChangeReplacesTheMirrorKeyByKeyLastWriterWins() {
        let fixture = Self.make(local: [Self.synced: .string("no"), Self.other: .string("0"), Self.device: .bool(false)])
        fixture.cloud.receive(SyncedStoreChange(reason: .serverChange), updates: [Self.synced: .string("yes"), Self.other: nil])
        fixture.store.apply(SyncedStoreChange(reason: .serverChange, keys: [Self.synced, Self.other, Self.device]))
        #expect(fixture.local.rawValue(forKey: Self.synced) == .string("yes"))
        #expect(fixture.local.rawValue(forKey: Self.other) == nil)
        #expect(fixture.local.rawValue(forKey: Self.device) == .bool(false))
    }

    @Test func theInitialSyncLetsTheCloudWinAndPushesWhatItLacks() {
        let fixture = Self.make(
            local: [Self.synced: .string("no"), Self.other: .string("1"), Self.device: .bool(true)],
            cloud: [Self.synced: .string("yes")]
        )
        fixture.store.apply(SyncedStoreChange(reason: .initialSync))
        #expect(fixture.local.rawValue(forKey: Self.synced) == .string("yes"))
        #expect(fixture.cloud.value(forKey: Self.other) == .string("1"))
        #expect(fixture.cloud.value(forKey: Self.device) == nil)
        #expect(fixture.cloud.value(forKey: SyncedSettingsStore.schemaVersionKey) == .int(1))
    }

    @Test func anAccountChangeQuarantinesAndTakesTheNewAccountsValuesAtOnce() throws {
        let fixture = Self.make(local: [Self.synced: .string("yes"), Self.device: .bool(true)], cloud: [Self.synced: .string("yes")])
        fixture.switchAccount(to: "account-2", cloudValues: [Self.other: .string("1")])
        let entry = try #require(fixture.deviceState.document?.quarantine["account-1"])
        #expect(entry.values == [Self.synced: .string("yes")])
        #expect(entry.savedAt == Self.start)
        // The mirror holds the new account's values only, without waiting for an initial sync that may never come.
        #expect(fixture.local.rawValue(forKey: Self.synced) == nil)
        #expect(fixture.local.rawValue(forKey: Self.other) == .string("1"))
        #expect(fixture.local.rawValue(forKey: Self.device) == .bool(true))
        #expect(fixture.cloud.value(forKey: Self.synced) == nil)
        #expect(fixture.deviceState.document?.knownIdentity == "account-2")
        // A write now belongs to the new account.
        fixture.store.setRawValue(.string("no"), forKey: Self.synced)
        #expect(fixture.cloud.value(forKey: Self.synced) == .string("no"))
    }

    @Test func quarantinedValuesComeBackWhenTheirAccountIsActiveAgain() {
        let fixture = Self.make(local: [Self.synced: .string("yes"), Self.other: .string("1")])
        fixture.switchAccount(to: "account-2")
        #expect(fixture.local.rawValue(forKey: Self.other) == nil)
        // Back to the first account, whose cloud now has another `display_sig` and lost `vos_sujets`.
        fixture.switchAccount(to: "account-1", cloudValues: [Self.synced: .string("no")])
        #expect(fixture.local.rawValue(forKey: Self.synced) == .string("no"))
        #expect(fixture.local.rawValue(forKey: Self.other) == .string("1"))
        #expect(fixture.cloud.value(forKey: Self.other) == .string("1"))
        #expect(fixture.deviceState.document?.quarantine["account-1"] == nil)
        // The second account's quarantine stays for it.
        #expect(fixture.deviceState.document?.quarantine["account-2"] != nil)
    }

    /// The account changed while the app was not running: the next launch sees it (Apple: compare the stored token).
    @Test func anAccountChangeWhileNotRunningIsHandledAtLaunch() throws {
        let fixture = Self.make(local: [Self.synced: .string("yes"), Self.other: .string("1")])
        fixture.switchAccount(to: "account-2", cloudValues: [Self.synced: .string("no")])
        #expect(fixture.local.rawValue(forKey: Self.synced) == .string("no"))
        // App killed; back to the first account in Settings; relaunch.
        fixture.cloud.receive(SyncedStoreChange(reason: .accountChange), updates: [Self.synced: .string("yes")], identity: "account-1")
        _ = fixture.relaunched()
        let second = try #require(fixture.deviceState.document?.quarantine["account-2"])
        #expect(second.values == [Self.synced: .string("no")])
        #expect(fixture.local.rawValue(forKey: Self.synced) == .string("yes"))
        #expect(fixture.local.rawValue(forKey: Self.other) == .string("1"))
        #expect(fixture.cloud.value(forKey: Self.other) == .string("1"))
        #expect(fixture.deviceState.document?.knownIdentity == "account-1")
    }

    @Test func aSignOutWhileNotRunningQuarantinesAtLaunch() {
        let fixture = Self.make(local: [Self.synced: .string("yes")])
        fixture.cloud.receive(SyncedStoreChange(reason: .accountChange), identity: .some(nil))
        _ = fixture.relaunched()
        #expect(fixture.local.rawValue(forKey: Self.synced) == nil)
        #expect(fixture.deviceState.document?.quarantine["account-1"]?.values == [Self.synced: .string("yes")])
        #expect(fixture.deviceState.document?.identityRecorded == true)
        #expect(fixture.deviceState.document?.knownIdentity == nil)
    }

    /// ADR 0013 §5 step 2: the values on the device (a legacy import) meet the cloud's at the first launch.
    @Test func aFirstLaunchRecordsTheAccountAndRunsTheInitialSyncRule() {
        let fixture = Self.make(
            local: [Self.synced: .string("yes"), Self.other: .string("1")],
            cloud: [Self.other: .string("0")],
            deviceState: InMemorySmallStorePersistence()
        )
        #expect(fixture.deviceState.document?.identityRecorded == true)
        #expect(fixture.deviceState.document?.knownIdentity == "account-1")
        #expect(fixture.deviceState.document?.quarantine.isEmpty == true)
        #expect(fixture.local.rawValue(forKey: Self.synced) == .string("yes"))
        #expect(fixture.cloud.value(forKey: Self.synced) == .string("yes"))
        #expect(fixture.local.rawValue(forKey: Self.other) == .string("0"))
        // The next launch changes nothing.
        fixture.store.setRawValue(.string("no"), forKey: Self.synced)
        fixture.cloud.removeValue(forKey: Self.other)
        _ = fixture.relaunched()
        #expect(fixture.local.rawValue(forKey: Self.other) == .string("0"))
        #expect(fixture.cloud.value(forKey: Self.other) == nil)
    }

    /// A first sign-in: values written without an Apple ID belong to none, so they stay and meet the cloud's.
    @Test func signingInKeepsTheValuesWrittenWithoutAnAccount() {
        let fixture = Self.make(local: [Self.synced: .string("yes"), Self.other: .string("1")], identity: nil)
        fixture.switchAccount(to: "account-2", cloudValues: [Self.other: .string("0")])
        #expect(fixture.local.rawValue(forKey: Self.synced) == .string("yes"))
        #expect(fixture.local.rawValue(forKey: Self.other) == .string("0"))
        #expect(fixture.cloud.value(forKey: Self.synced) == .string("yes"))
        #expect(fixture.deviceState.document?.quarantine.isEmpty == true)
    }

    @Test func aQuarantineIsDeletedAfterNinetyDays() {
        let old = SyncQuarantineEntry(savedAt: Self.start.addingTimeInterval(-91 * 86_400), values: [Self.synced: .string("yes")])
        let recent = SyncQuarantineEntry(savedAt: Self.start.addingTimeInterval(-89 * 86_400), values: [Self.synced: .string("no")])
        let document = SyncDeviceStateDocument(
            identityRecorded: true, knownIdentity: "account-1", quarantine: ["old": old, "recent": recent]
        )
        let fixture = Self.make(deviceState: InMemorySmallStorePersistence(document))
        #expect(fixture.deviceState.document?.quarantine.keys.sorted() == ["recent"])
        fixture.clock.advance(days: 2)
        fixture.store.apply(SyncedStoreChange(reason: .initialSync))
        #expect(fixture.deviceState.document?.quarantine.isEmpty == true)
    }

    @Test func aQuarantineThatCannotBeSavedStaysInMemoryAndIsNeverUploaded() {
        let persistence = FailingSmallStorePersistence<SyncDeviceStateDocument>(
            SyncDeviceStateDocument(identityRecorded: true, knownIdentity: "account-1")
        )
        persistence.failsToSave = true
        let local = InMemorySettingsStore([Self.synced: .string("yes")])
        let cloud = InMemorySyncedKeyValueStore()
        let store = SyncedSettingsStore(local: local, cloud: cloud, deviceState: persistence)
        cloud.receive(SyncedStoreChange(reason: .accountChange), identity: "account-2")
        store.apply(SyncedStoreChange(reason: .accountChange))
        #expect(store.deviceStateFailure != nil)
        #expect(local.rawValue(forKey: Self.synced) == nil)
        #expect(cloud.value(forKey: Self.synced) == nil)
        // Back to the first account during the same run: the values kept in memory come back.
        cloud.receive(SyncedStoreChange(reason: .accountChange), identity: "account-1")
        store.apply(SyncedStoreChange(reason: .accountChange))
        #expect(local.rawValue(forKey: Self.synced) == .string("yes"))
    }

    @Test func aQuotaViolationKeepsTheLocalValue() {
        let fixture = Self.make()
        fixture.store.setRawValue(.string("yes"), forKey: Self.synced)
        fixture.cloud.receive(SyncedStoreChange(reason: .quotaViolation, keys: [Self.synced]), updates: [Self.synced: nil])
        fixture.store.apply(SyncedStoreChange(reason: .quotaViolation, keys: [Self.synced, Self.device]))
        #expect(fixture.local.rawValue(forKey: Self.synced) == .string("yes"))
        #expect(fixture.store.quotaViolations == [Self.synced])
    }

    @Test func aNewerSchemaIsNeitherAppliedNorOverwritten() {
        let fixture = Self.make(
            local: [Self.synced: .string("no"), Self.other: .string("1")],
            cloud: [SyncedSettingsStore.schemaVersionKey: .int(2), Self.synced: .data(Data([1]))]
        )
        fixture.store.setRawValue(.string("yes"), forKey: Self.synced)
        #expect(fixture.cloud.value(forKey: Self.synced) == .data(Data([1])))
        fixture.store.apply(SyncedStoreChange(reason: .serverChange, keys: [Self.synced]))
        fixture.store.apply(SyncedStoreChange(reason: .initialSync))
        #expect(fixture.local.rawValue(forKey: Self.synced) == .string("yes"))
        #expect(fixture.cloud.value(forKey: Self.other) == nil)
        #expect(fixture.cloud.value(forKey: SyncedSettingsStore.schemaVersionKey) == .int(2))
    }

    /// A local store that, during a write, lets another thread apply a server change, and waits up to 0.5 s for it.
    final class RacingSettingsStore: SettingsStore, @unchecked Sendable {
        // Only the first write races; the test drives one write.
        let inner = InMemorySettingsStore()
        var duringFirstWrite: (@Sendable () -> Void)?

        func rawValue(forKey key: String) -> SettingRawValue? { inner.rawValue(forKey: key) }
        func removeValue(forKey key: String) { inner.removeValue(forKey: key) }
        func setRawValue(_ value: SettingRawValue, forKey key: String) {
            inner.setRawValue(value, forKey: key)
            if let race = duringFirstWrite {
                duringFirstWrite = nil
                race()
            }
        }
    }

    @Test(.timeLimit(.minutes(1))) func aWriteAndAServerChangeNeverInterleave() {
        let local = RacingSettingsStore()
        let cloud = InMemorySyncedKeyValueStore()
        let store = SyncedSettingsStore(local: local, cloud: cloud, deviceState: InMemorySmallStorePersistence())
        let applied = DispatchSemaphore(value: 0)
        local.duringFirstWrite = {
            Thread.detachNewThread {
                cloud.receive(SyncedStoreChange(reason: .serverChange), updates: [Self.synced: .string("no")])
                store.apply(SyncedStoreChange(reason: .serverChange, keys: [Self.synced]))
                applied.signal()
            }
            // With one critical section per operation the change cannot run now: this wait times out.
            _ = applied.wait(timeout: .now() + 0.5)
        }
        store.setRawValue(.string("yes"), forKey: Self.synced)
        _ = applied.wait(timeout: .now() + 5)
        #expect(local.rawValue(forKey: Self.synced) == cloud.value(forKey: Self.synced)?.settingRawValue)
    }

    @Test(.timeLimit(.minutes(1))) func runAppliesTheStoreChangesAsTheyCome() async throws {
        let fixture = Self.make()
        let running = Task { await fixture.store.run() }
        // `run` subscribes asynchronously: replay the change until it lands, a bounded number of times (a change that is
        // never applied must fail the test, not hang it).
        for _ in 0..<1_000 where fixture.local.rawValue(forKey: Self.synced) == nil {
            fixture.cloud.receive(SyncedStoreChange(reason: .serverChange, keys: [Self.synced]), updates: [Self.synced: .string("yes")])
            try await Task.sleep(for: .milliseconds(1))
        }
        running.cancel()
        #expect(fixture.local.rawValue(forKey: Self.synced) == .string("yes"))
    }

    @Test func theDeviceStateSurvivesAReopenedFile() throws {
        let directory = try SmallStoreTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "sync-device-state.json")
        let local = InMemorySettingsStore([Self.synced: .string("yes"), "theme_night_brightness": .double(0.5)])
        let cloud = InMemorySyncedKeyValueStore()
        let store = SyncedSettingsStore(local: local, cloud: cloud, deviceState: FileSmallStorePersistence(fileURL: file))
        cloud.receive(SyncedStoreChange(reason: .accountChange), identity: .some(nil))
        store.apply(SyncedStoreChange(reason: .accountChange))
        let reopened = try FileSmallStorePersistence<SyncDeviceStateDocument>(fileURL: file).load()
        #expect(reopened?.quarantine["account-1"]?.values == [Self.synced: .string("yes"), "theme_night_brightness": .double(0.5)])
        #expect(reopened?.identityRecorded == true)
        #expect(reopened?.knownIdentity == nil)
    }
}
