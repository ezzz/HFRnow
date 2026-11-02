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
        let quarantine: InMemorySmallStorePersistence<SyncQuarantineDocument>
        let clock: Clock
    }

    private static func make(
        local: [String: SettingRawValue] = [:],
        cloud: [String: SyncedValue] = [:],
        identity: String? = "account-1",
        quarantine: InMemorySmallStorePersistence<SyncQuarantineDocument> = InMemorySmallStorePersistence()
    ) -> Fixture {
        let localStore = InMemorySettingsStore(local)
        let cloudStore = InMemorySyncedKeyValueStore(cloud, identity: identity)
        let clock = Clock()
        let store = SyncedSettingsStore(
            local: localStore, cloud: cloudStore, quarantine: quarantine, clock: { clock.now }
        )
        return Fixture(store: store, local: localStore, cloud: cloudStore, quarantine: quarantine, clock: clock)
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
        fixture.store.setRawValue(.string("no"), forKey: Self.synced)
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

    @Test func anAccountChangeQuarantinesBlocksAndNeverUploadsThePreviousValues() throws {
        let fixture = Self.make(local: [Self.synced: .string("yes"), Self.device: .bool(true)], cloud: [Self.synced: .string("yes")])
        // Another Apple ID: the store now holds that account's values.
        fixture.cloud.receive(SyncedStoreChange(reason: .accountChange), updates: [Self.other: .string("1")], identity: "account-2")
        fixture.store.apply(SyncedStoreChange(reason: .accountChange))
        let entry = try #require(fixture.quarantine.document?.entries["account-1"])
        #expect(entry.values == [Self.synced: .string("yes")])
        #expect(entry.savedAt == Self.start)
        #expect(fixture.local.rawValue(forKey: Self.synced) == nil)
        #expect(fixture.local.rawValue(forKey: Self.device) == .bool(true))
        #expect(fixture.store.waitsForInitialSync)

        // Blocked: writes stay local, server changes are not applied.
        fixture.store.setRawValue(.string("no"), forKey: Self.synced)
        #expect(fixture.cloud.value(forKey: Self.synced) == nil)
        fixture.store.apply(SyncedStoreChange(reason: .serverChange, keys: [Self.other]))
        #expect(fixture.local.rawValue(forKey: Self.other) == nil)

        // The new account's initial sync: its values win, what it lacks is pushed (only what was written meanwhile).
        fixture.store.apply(SyncedStoreChange(reason: .initialSync))
        #expect(!fixture.store.waitsForInitialSync)
        #expect(fixture.local.rawValue(forKey: Self.other) == .string("1"))
        #expect(fixture.cloud.value(forKey: Self.synced) == .string("no"))
        // The previous account's values stay quarantined: never restored into another account.
        #expect(fixture.quarantine.document?.entries["account-1"] != nil)
    }

    @Test func quarantinedValuesComeBackWhenTheirAccountIsActiveAgain() {
        let fixture = Self.make(local: [Self.synced: .string("yes"), Self.other: .string("1")])
        fixture.cloud.receive(SyncedStoreChange(reason: .accountChange), identity: "account-2")
        fixture.store.apply(SyncedStoreChange(reason: .accountChange))
        fixture.store.apply(SyncedStoreChange(reason: .initialSync))
        // Back to the first account, whose cloud now has another `display_sig`.
        fixture.cloud.receive(SyncedStoreChange(reason: .accountChange), updates: [Self.synced: .string("no")], identity: "account-1")
        fixture.store.apply(SyncedStoreChange(reason: .accountChange))
        fixture.store.apply(SyncedStoreChange(reason: .initialSync))
        #expect(fixture.local.rawValue(forKey: Self.synced) == .string("no"))
        #expect(fixture.local.rawValue(forKey: Self.other) == .string("1"))
        #expect(fixture.cloud.value(forKey: Self.other) == .string("1"))
        #expect(fixture.quarantine.document?.entries["account-1"] == nil)
    }

    /// A first sign-in: values written without an Apple ID belong to none, so they stay and meet the cloud's.
    @Test func signingInKeepsTheValuesWrittenWithoutAnAccount() {
        let fixture = Self.make(local: [Self.synced: .string("yes"), Self.other: .string("1")], identity: nil)
        fixture.cloud.receive(SyncedStoreChange(reason: .accountChange), updates: [Self.other: .string("0")], identity: "account-2")
        fixture.store.apply(SyncedStoreChange(reason: .accountChange))
        #expect(fixture.local.rawValue(forKey: Self.synced) == .string("yes"))
        #expect(fixture.store.waitsForInitialSync)
        #expect(fixture.quarantine.document == nil)
        fixture.store.apply(SyncedStoreChange(reason: .initialSync))
        #expect(fixture.local.rawValue(forKey: Self.other) == .string("0"))
        #expect(fixture.cloud.value(forKey: Self.synced) == .string("yes"))
    }

    @Test func aQuarantineIsDeletedAfterNinetyDays() {
        let old = SyncQuarantineEntry(savedAt: Self.start.addingTimeInterval(-91 * 86_400), values: [Self.synced: .string("yes")])
        let recent = SyncQuarantineEntry(savedAt: Self.start.addingTimeInterval(-89 * 86_400), values: [Self.synced: .string("no")])
        let persistence = InMemorySmallStorePersistence(SyncQuarantineDocument(entries: ["old": old, "recent": recent]))
        let fixture = Self.make(quarantine: persistence)
        #expect(fixture.quarantine.document?.entries.keys.sorted() == ["recent"])
        fixture.clock.advance(days: 2)
        fixture.store.apply(SyncedStoreChange(reason: .initialSync))
        #expect(fixture.quarantine.document?.entries.isEmpty == true)
    }

    @Test func aQuarantineThatCannotBeSavedStaysInMemoryAndIsNeverUploaded() {
        let persistence = FailingSmallStorePersistence<SyncQuarantineDocument>()
        persistence.failsToSave = true
        let local = InMemorySettingsStore([Self.synced: .string("yes")])
        let cloud = InMemorySyncedKeyValueStore()
        let store = SyncedSettingsStore(local: local, cloud: cloud, quarantine: persistence)
        cloud.receive(SyncedStoreChange(reason: .accountChange), identity: "account-2")
        store.apply(SyncedStoreChange(reason: .accountChange))
        #expect(store.quarantineFailure != nil)
        #expect(local.rawValue(forKey: Self.synced) == nil)
        store.apply(SyncedStoreChange(reason: .initialSync))
        #expect(cloud.value(forKey: Self.synced) == nil)
        // Back to the first account: the values kept in memory come back.
        cloud.receive(SyncedStoreChange(reason: .accountChange), identity: "account-1")
        store.apply(SyncedStoreChange(reason: .accountChange))
        store.apply(SyncedStoreChange(reason: .initialSync))
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

    @Test func runAppliesTheStoreChangesAsTheyCome() async {
        let fixture = Self.make()
        let running = Task { await fixture.store.run() }
        // Let `run` subscribe before the change is played.
        while fixture.local.rawValue(forKey: Self.synced) == nil {
            fixture.cloud.receive(SyncedStoreChange(reason: .serverChange, keys: [Self.synced]), updates: [Self.synced: .string("yes")])
            await Task.yield()
        }
        running.cancel()
        #expect(fixture.local.rawValue(forKey: Self.synced) == .string("yes"))
    }

    @Test func aQuarantineSurvivesAReopenedFile() async throws {
        let directory = try SmallStoreTestSupport.makeDirectory()
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "sync-quarantine.json")
        let local = InMemorySettingsStore([Self.synced: .string("yes"), "theme_night_brightness": .double(0.5)])
        let cloud = InMemorySyncedKeyValueStore()
        let store = SyncedSettingsStore(local: local, cloud: cloud, quarantine: FileSmallStorePersistence(fileURL: file))
        cloud.receive(SyncedStoreChange(reason: .accountChange), identity: nil)
        store.apply(SyncedStoreChange(reason: .accountChange))
        let reopened = try FileSmallStorePersistence<SyncQuarantineDocument>(fileURL: file).load()
        #expect(reopened?.entries["account-1"]?.values == [Self.synced: .string("yes"), "theme_night_brightness": .double(0.5)])
    }
}
