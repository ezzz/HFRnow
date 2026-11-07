import Foundation
import HFRModels
import Synchronization
import Testing
@testable import HFRStorage

/// Apple ID changes and `run()` for the list sync (LOT-172 part 2, ADR 0013 Amendment 2).
extension SyncedListsStoreTests {
    // MARK: Apple ID

    @Test func aSignOutKeepsTheListsAndPushesNothingUntilTheSameAppleIDReturns() async throws {
        let fixture = await Self.make(cloud: [Self.superKey: Self.envelope([Self.favorite()])])
        await fixture.switchAppleID(to: nil)
        #expect(await fixture.superFavorites.favorites(for: "Alice") == [Self.favorite()])
        try await fixture.pseudoLists.allow("Friend")
        await fixture.sync.handle(.listsChanged)
        #expect(fixture.cloud.values.isEmpty)
        #expect(fixture.quarantine().isEmpty)

        await fixture.switchAppleID(to: "apple-1", values: [Self.superKey: Self.envelope([Self.favorite()])])
        #expect(await fixture.superFavorites.favorites(for: "Alice") == [Self.favorite()])
        #expect(fixture.cloud.value(forKey: SyncedListsStore.allowlistKey) != nil)
        #expect(fixture.quarantine().isEmpty)
    }

    @Test func changesMadeWhileSignedOutArePushedWhenTheSameAppleIDReturns() async throws {
        let fixture = await Self.make(cloud: [Self.superKey: Self.envelope([Self.favorite()])])
        await fixture.switchAppleID(to: nil)
        try await fixture.superFavorites.add(Self.other, account: "Alice", at: Self.start)
        await fixture.sync.handle(.listsChanged)
        // A relaunch while signed out keeps the knowledge of what was last synced.
        let relaunched = await fixture.relaunched()
        let change = SyncedStoreChange(reason: .accountChange)
        fixture.cloud.receive(change, updates: [Self.superKey: Self.envelope([Self.favorite()])], identity: .some("apple-1"))
        await relaunched.handle(.cloud(change))
        #expect(fixture.cloudSuperFavorites()?.map(\.topic) == [Self.other, Self.topic])
        #expect(await fixture.superFavorites.favorites(for: "Alice").count == 2)
    }

    @Test func aMissedAppleIDChangeIsHandledOnAnyNotification() async throws {
        let fixture = await Self.make(cloud: [Self.superKey: Self.envelope([Self.favorite()])])
        fixture.cloud.receive(SyncedStoreChange(reason: .accountChange), updates: [:], identity: .some("apple-2"))
        await fixture.sync.handle(.cloud(SyncedStoreChange(reason: .initialSync)))
        #expect(await fixture.superFavorites.favorites(for: "Alice").isEmpty)
        #expect(fixture.quarantine()["apple-1"]?.values[Self.superKey] != nil)
    }

    @Test func anotherAppleIDGetsItsOwnListsAndTheFirstOnesComeBackWithIt() async throws {
        let fixture = await Self.make(cloud: [Self.superKey: Self.envelope([Self.favorite()])])
        try await fixture.pseudoLists.allow("Friend")
        try await fixture.positions.advance(Self.topic, to: Self.position(page: 2, at: 0), account: "Alice")
        await fixture.sync.handle(.listsChanged)

        await fixture.switchAppleID(to: "apple-2", values: [Self.superKey: Self.envelope([Self.favorite(Self.other)])])
        #expect(await fixture.superFavorites.favorites(for: "Alice") == [Self.favorite(Self.other)])
        #expect(await fixture.pseudoLists.allowlist().isEmpty)
        #expect(await fixture.positions.records(for: "Alice").isEmpty)
        // Nothing of the first Apple ID went to the second's store.
        #expect(fixture.cloud.value(forKey: SyncedListsStore.allowlistKey) == nil)
        #expect(fixture.cloud.value(forKey: Self.positionsKey) == nil)
        #expect(Self.lists(fixture.quarantine()["apple-1"]) == [SyncedListsStore.allowlistKey, "positions.Alice", Self.superKey])

        await fixture.switchAppleID(to: "apple-1", values: [:])
        #expect(await fixture.superFavorites.favorites(for: "Alice") == [Self.favorite()])
        #expect(await fixture.pseudoLists.allowlist().map(\.pseudo) == ["Friend"])
        #expect(await fixture.positions.position(of: Self.topic, account: "Alice")?.page == 2)
        #expect(fixture.quarantine()["apple-1"] == nil)
        #expect(Self.lists(fixture.quarantine()["apple-2"]) == [Self.superKey])
    }

    /// The lists of a quarantine entry, digests left out.
    static func lists(_ entry: SyncQuarantineEntry?) -> [String] {
        (entry?.values.keys.filter { !$0.hasPrefix(SyncedListsStore.digestPrefix) } ?? []).sorted()
    }

    @Test func aChangeMadeWhileSignedOutSurvivesAnotherAppleIDInBetween() async throws {
        let fixture = await Self.make(cloud: [Self.superKey: Self.envelope([Self.favorite()])])
        await fixture.switchAppleID(to: nil)
        try await fixture.superFavorites.add(Self.other, account: "Alice", at: Self.start)
        await fixture.switchAppleID(to: "apple-2")
        await fixture.switchAppleID(to: "apple-1", values: [Self.superKey: Self.envelope([Self.favorite()])])
        #expect(fixture.cloudSuperFavorites()?.map(\.topic) == [Self.other, Self.topic])
    }

    @Test func aSignedOutChangeInAStoreUnreadableAtTheSwitchKeepsItsDigest() async throws {
        let fixture = await Self.make(cloud: [Self.superKey: Self.envelope([Self.favorite()])])
        await fixture.switchAppleID(to: nil)
        try await fixture.superFavorites.add(Self.other, account: "Alice", at: Self.start)
        fixture.superFavoritePersistence.failsToLoad = true
        await fixture.superFavorites.reload()
        await fixture.switchAppleID(to: "apple-2")
        fixture.superFavoritePersistence.failsToLoad = false
        await fixture.superFavorites.reload()
        await fixture.sync.handle(.listsChanged)
        await fixture.switchAppleID(to: "apple-1", values: [Self.superKey: Self.envelope([Self.favorite()])])
        #expect(fixture.cloudSuperFavorites()?.map(\.topic) == [Self.other, Self.topic])
    }

    @Test func aSignedOutChangeInAStoreUnreadableAcrossBothSwitchesKeepsItsDigest() async throws {
        let fixture = await Self.make(cloud: [Self.superKey: Self.envelope([Self.favorite()])])
        await fixture.switchAppleID(to: nil)
        try await fixture.superFavorites.add(Self.other, account: "Alice", at: Self.start)
        fixture.superFavoritePersistence.failsToLoad = true
        await fixture.superFavorites.reload()
        await fixture.switchAppleID(to: "apple-2")
        await fixture.switchAppleID(to: "apple-1", values: [Self.superKey: Self.envelope([Self.favorite()])])
        await fixture.sync.handle(.listsChanged)
        fixture.superFavoritePersistence.failsToLoad = false
        await fixture.superFavorites.reload()
        await fixture.sync.handle(.listsChanged)
        #expect(fixture.cloudSuperFavorites()?.map(\.topic) == [Self.other, Self.topic])
        #expect(await fixture.superFavorites.favorites(for: "Alice").count == 2)
    }

    @Test func aStaleStoreRecoveringRestoresOnlyItsOwnLists() async throws {
        let aside = SyncQuarantineEntry(
            savedAt: Self.start, values: [SyncedListsStore.allowlistKey: Self.envelope([PseudoListEntry(pseudo: "Kept")])]
        )
        let superPersistence = FailingSmallStorePersistence<SuperFavoritesDocument>()
        let smileyPersistence = FailingSmallStorePersistence<AppSmileyFavoritesDocument>()
        superPersistence.failsToLoad = true
        smileyPersistence.failsToLoad = true
        let pseudoLists = PseudoListStore(persistence: InMemoryPseudoListPersistence())
        let superFavorites = SuperFavoritesStore(persistence: superPersistence)
        let smileyFavorites = AppSmileyFavoritesStore(persistence: smileyPersistence)
        await superFavorites.reload()
        await smileyFavorites.reload()
        _ = try await pseudoLists.allow("Mine")
        let sync = SyncedListsStore(
            cloud: InMemorySyncedKeyValueStore(identity: "apple-1"), pseudoLists: pseudoLists,
            superFavorites: superFavorites, smileyFavorites: smileyFavorites,
            positions: ReadingPositionStore(persistence: FlakyPositionPersistence()),
            deviceState: FailingSmallStorePersistence(SyncedListsDeviceState(
                owner: "apple-1", stale: ["superfavorites": "apple-0", "smileyfavorites": "apple-0"],
                quarantine: ["apple-1": aside]
            )),
            accounts: { ["Alice"] }, clock: { Self.start }, sleep: { _ in }
        )
        await sync.start()
        smileyPersistence.failsToLoad = false
        await smileyFavorites.reload()
        await sync.handle(.listsChanged)
        _ = try await pseudoLists.replaceAllowlist(with: [])
        await sync.handle(.listsChanged)
        // Another store recovering later never refills the allowlist the user emptied.
        superPersistence.failsToLoad = false
        await superFavorites.reload()
        await sync.handle(.listsChanged)
        #expect(await pseudoLists.allowlist().isEmpty)
    }

    @Test func aListEmptiedAfterADeferredRestoreIsNotRefilled() async throws {
        let second = SyncQuarantineEntry(savedAt: Self.start, values: [Self.superKey: Self.envelope([Self.favorite(Self.other)])])
        let fixture = await Self.make(deviceState: SyncedListsDeviceState(owner: "apple-1", quarantine: ["apple-2": second]))
        fixture.deviceState.failsToSave = true
        await fixture.switchAppleID(to: "apple-2")
        try await fixture.superFavorites.add(Self.topic, account: "Alice", at: Self.start)
        fixture.deviceState.failsToSave = false
        await fixture.sync.handle(.listsChanged)
        // The deferred restore found a list already there: the quarantined one stays aside.
        #expect(await fixture.superFavorites.favorites(for: "Alice") == [Self.favorite()])
        try await fixture.superFavorites.remove(Self.topic, account: "Alice")
        await fixture.sync.handle(.listsChanged)
        #expect(await fixture.superFavorites.favorites(for: "Alice").isEmpty)
        #expect(fixture.cloudSuperFavorites() == [])
    }

    @Test func anAppleIDChangeWhileNotRunningIsHandledAtLaunchAfterTheStoreSpeaks() async throws {
        let fixture = await Self.make(cloud: [Self.superKey: Self.envelope([Self.favorite()])])
        // The app stops; the system switches to another Apple ID.
        fixture.cloud.receive(
            SyncedStoreChange(reason: .accountChange),
            updates: [Self.superKey: Self.envelope([Self.favorite(Self.other)])], identity: .some("apple-2")
        )
        let sync = await fixture.relaunched()
        #expect(await fixture.superFavorites.favorites(for: "Alice").isEmpty)
        #expect(fixture.quarantine()["apple-1"] != nil)
        await sync.handle(.graceEnded)
        #expect(await fixture.superFavorites.favorites(for: "Alice") == [Self.favorite(Self.other)])
    }

    @Test func aStoreUnreadableAtTheChangeIsSetAsideOnceReadableAndNeverPushed() async throws {
        let fixture = await Self.make()
        try await fixture.superFavorites.add(Self.topic, account: "Alice", at: Self.start)
        await fixture.sync.handle(.listsChanged)
        fixture.superFavoritePersistence.failsToLoad = true
        await fixture.superFavorites.reload()
        await fixture.switchAppleID(to: "apple-2")

        fixture.superFavoritePersistence.failsToLoad = false
        await fixture.superFavorites.reload()
        await fixture.sync.handle(.listsChanged)
        #expect(fixture.cloud.value(forKey: Self.superKey) == nil)
        #expect(await fixture.superFavorites.favorites(for: "Alice").isEmpty)
        #expect(fixture.quarantine()["apple-1"]?.values[Self.superKey] != nil)
    }

    @Test func aStoreThatCannotBeEmptiedAtTheChangeIsNeverPushedUnderTheNewAppleID() async throws {
        let fixture = await Self.make()
        try await fixture.superFavorites.add(Self.topic, account: "Alice", at: Self.start)
        await fixture.sync.handle(.listsChanged)
        fixture.superFavoritePersistence.failsToSave = true
        await fixture.switchAppleID(to: "apple-2")
        // Readable, still holding the first Apple ID's list: a later event must not push it.
        #expect(await fixture.superFavorites.favorites(for: "Alice") == [Self.favorite()])
        try await fixture.pseudoLists.allow("Friend")
        await fixture.sync.handle(.listsChanged)
        await fixture.sync.handle(.accountsChanged)
        #expect(fixture.cloud.value(forKey: Self.superKey) == nil)
        #expect(fixture.cloud.value(forKey: SyncedListsStore.allowlistKey) != nil)

        fixture.superFavoritePersistence.failsToSave = false
        await fixture.sync.handle(.listsChanged)
        #expect(await fixture.superFavorites.favorites(for: "Alice").isEmpty)
        #expect(fixture.cloud.value(forKey: Self.superKey) == nil)
        #expect(fixture.quarantine()["apple-1"]?.values[Self.superKey] != nil)
    }

    @Test func aListThatCannotComeBackStaysInTheQuarantineUntilItCan() async throws {
        let second = SyncQuarantineEntry(savedAt: Self.start, values: [Self.superKey: Self.envelope([Self.favorite(Self.other)])])
        let fixture = await Self.make(deviceState: SyncedListsDeviceState(owner: "apple-1", quarantine: ["apple-2": second]))
        try await fixture.superFavorites.add(Self.topic, account: "Alice", at: Self.start)
        await fixture.sync.handle(.listsChanged)
        fixture.superFavoritePersistence.failsToLoad = true
        await fixture.superFavorites.reload()
        await fixture.switchAppleID(to: "apple-2")
        #expect(fixture.quarantine()["apple-2"]?.values[Self.superKey] != nil)

        fixture.superFavoritePersistence.failsToLoad = false
        await fixture.superFavorites.reload()
        await fixture.sync.handle(.listsChanged)
        #expect(await fixture.superFavorites.favorites(for: "Alice") == [Self.favorite(Self.other)])
        #expect(fixture.quarantine()["apple-1"]?.values[Self.superKey] != nil)
        #expect(fixture.quarantine()["apple-2"] == nil)
    }

    /// A switch the test arms.
    final class Trigger: Sendable {
        private let armed = Mutex(false)
        var isArmed: Bool { armed.withLock { $0 } }
        func arm() { armed.withLock { $0 = true } }
    }

    @Test func aPushStartedBeforeAnAppleIDSwitchNeverWritesIntoTheNewAppleIDsStore() async throws {
        let cloud = InMemorySyncedKeyValueStore(identity: "apple-1")
        let superFavorites = SuperFavoritesStore(persistence: InMemorySmallStorePersistence<SuperFavoritesDocument>())
        let trigger = Trigger()
        let sync = SyncedListsStore(
            cloud: cloud, pseudoLists: PseudoListStore(persistence: InMemoryPseudoListPersistence()),
            superFavorites: superFavorites,
            smileyFavorites: AppSmileyFavoritesStore(persistence: InMemorySmallStorePersistence<AppSmileyFavoritesDocument>()),
            positions: ReadingPositionStore(persistence: FlakyPositionPersistence()),
            deviceState: FailingSmallStorePersistence(SyncedListsDeviceState(owner: "apple-1")),
            accounts: {
                // The system switches the Apple ID while the push waits; its notification is handled later.
                if trigger.isArmed { cloud.receive(SyncedStoreChange(reason: .accountChange), identity: .some("apple-2")) }
                return ["Alice"]
            },
            sleep: { _ in }
        )
        await sync.start()
        try await superFavorites.add(Self.topic, account: "Alice", at: Self.start)
        trigger.arm()
        await sync.handle(.listsChanged)
        #expect(cloud.accountIdentity() == "apple-2")
        #expect(cloud.values.isEmpty)
    }

    @Test func anUnwritableDeviceFileAtASwitchPausesTheSync() async throws {
        let fixture = await Self.make(cloud: [Self.superKey: Self.envelope([Self.favorite()])])
        fixture.deviceState.failsToSave = true
        await fixture.switchAppleID(to: "apple-2")
        try await fixture.superFavorites.add(Self.other, account: "Alice", at: Self.start)
        await fixture.sync.handle(.listsChanged)
        #expect(fixture.cloud.values.isEmpty)
        #expect(fixture.deviceState.saved?.owner == "apple-1")

        fixture.deviceState.failsToSave = false
        await fixture.sync.handle(.listsChanged)
        #expect(fixture.deviceState.saved?.owner == "apple-2")
        // The store kept apple-1's list until the file could hold it: the add made meanwhile went aside with it.
        #expect(fixture.cloud.value(forKey: Self.superKey) == nil)
        #expect(await fixture.superFavorites.favorites(for: "Alice").isEmpty)
        let aside = fixture.quarantine()["apple-1"]?.values[Self.superKey]
        #expect(aside.flatMap { SyncedListEnvelope<SuperFavorite>($0)?.items }?.count == 2)
    }

    @Test func aSwitchWhoseQuarantineCannotBeSavedLosesNoListAtAKill() async throws {
        let fixture = await Self.make()
        try await fixture.superFavorites.add(Self.topic, account: "Alice", at: Self.start)
        await fixture.sync.handle(.listsChanged)
        fixture.deviceState.failsToSave = true
        await fixture.switchAppleID(to: "apple-2")
        // The process dies before any save succeeds; the next launch reads the file as it was.
        fixture.deviceState.failsToSave = false
        _ = await fixture.relaunched()
        let local = await fixture.superFavorites.favorites(for: "Alice")
        let aside = fixture.quarantine()["apple-1"]?.values[Self.superKey].flatMap { SyncedListEnvelope<SuperFavorite>($0)?.items }
        #expect(local == [Self.favorite()] || aside == [Self.favorite()])
    }

    @Test func aSwitchPausedByTheDeviceFileRestoresOnceItCanSave() async throws {
        let second = SyncQuarantineEntry(savedAt: Self.start, values: [Self.superKey: Self.envelope([Self.favorite(Self.other)])])
        let fixture = await Self.make(deviceState: SyncedListsDeviceState(owner: "apple-1", quarantine: ["apple-2": second]))
        fixture.deviceState.failsToSave = true
        await fixture.switchAppleID(to: "apple-2")
        #expect(await fixture.superFavorites.favorites(for: "Alice").isEmpty)

        fixture.deviceState.failsToSave = false
        await fixture.sync.handle(.listsChanged)
        #expect(await fixture.superFavorites.favorites(for: "Alice") == [Self.favorite(Self.other)])
        #expect(fixture.quarantine()["apple-2"] == nil)
    }

    @Test func aResumedSyncRunsTheInitialSyncRuleForListsAndPositions() async throws {
        let positions = [ReadingPositionRecord(topic: Self.other, position: Self.position(page: 7, at: 5))]
        let fixture = await Self.make(cloud: [Self.superKey: Self.envelope([Self.favorite()])])
        fixture.deviceState.failsToSave = true
        let second: [String: SyncedValue?] = [
            Self.superKey: Self.envelope([Self.favorite(Self.other)]), Self.positionsKey: Self.envelope(positions)
        ]
        await fixture.switchAppleID(to: "apple-2", values: second)
        // The store keeps apple-1's list until the file can hold it, so an add made while the sync is paused goes
        // aside with it; the new Apple ID's cloud list is never overwritten by a list built over that store.
        try await fixture.superFavorites.add(Self.topic, account: "Alice", at: Self.start)
        fixture.deviceState.failsToSave = false
        await fixture.sync.handle(.listsChanged)
        #expect(fixture.quarantine()["apple-1"]?.values[Self.superKey] != nil)
        #expect(await fixture.superFavorites.favorites(for: "Alice") == [Self.favorite(Self.other)])
        #expect(fixture.cloudSuperFavorites() == [Self.favorite(Self.other)])
        #expect(await fixture.positions.position(of: Self.other, account: "Alice")?.page == 7)
    }

    @Test func aQuarantineKeptInMemoryReachesTheFileOnceItCanBeSaved() async throws {
        let fixture = await Self.make()
        try await fixture.superFavorites.add(Self.topic, account: "Alice", at: Self.start)
        await fixture.sync.handle(.listsChanged)
        fixture.deviceState.failsToSave = true
        await fixture.switchAppleID(to: "apple-2")
        #expect(fixture.quarantine()["apple-1"] == nil)
        // Not emptied while only the memory holds its list.
        #expect(await fixture.superFavorites.favorites(for: "Alice") == [Self.favorite()])
        fixture.deviceState.failsToSave = false
        await fixture.sync.handle(.listsChanged)
        #expect(fixture.quarantine()["apple-1"]?.values[Self.superKey] != nil)
    }

    @Test func aDocumentWithoutTheNewerFieldsStillLoads() throws {
        let decoder = JSONDecoder()
        let document = try decoder.decode(SyncedListsDeviceState.self, from: Data(#"{"version":1,"owner":"apple-1"}"#.utf8))
        #expect(document.owner == "apple-1")
        #expect(document.synced.isEmpty && document.stale.isEmpty && document.quarantine.isEmpty)
    }

    @Test func quarantinedListsAreDeletedAfterNinetyDays() async throws {
        let old = SyncQuarantineEntry(savedAt: Self.start, values: [Self.superKey: Self.envelope([Self.favorite()])])
        let fixture = await Self.make(deviceState: SyncedListsDeviceState(owner: "apple-1", quarantine: ["apple-0": old]))
        #expect(fixture.quarantine()["apple-0"] != nil)
        fixture.clock.advance(seconds: SyncedSettingsStore.quarantineLifetime + 1)
        _ = await fixture.relaunched()
        #expect(fixture.quarantine().isEmpty)
    }

    @Test func anUnreadableDeviceFileStopsTheSync() async throws {
        let failing = FailingSmallStorePersistence<SyncedListsDeviceState>()
        failing.failsToLoad = true
        let fixture = await Self.make()
        let sync = SyncedListsStore(
            cloud: fixture.cloud, pseudoLists: fixture.pseudoLists, superFavorites: fixture.superFavorites,
            smileyFavorites: fixture.smileyFavorites, positions: fixture.positions, deviceState: failing,
            accounts: { ["Alice"] }, sleep: { _ in }
        )
        await sync.start()
        try await fixture.superFavorites.add(Self.topic, account: "Alice", at: Self.start)
        await sync.handle(.listsChanged)
        #expect(fixture.cloud.value(forKey: Self.superKey) == nil)
        #expect(await sync.deviceStateFailure != nil)
    }

    // MARK: run()

    @Test func runPushesAStoreChangeAsItIsSaved() async throws {
        let fixture = await Self.make()
        let sync = await fixture.relaunched()
        let running = Task { await sync.run() }
        defer { running.cancel() }
        for _ in 0..<1000 where await !sync.isRunning {
            try await Task.sleep(for: .milliseconds(1))
        }
        // Past the launch: the save below reaches the sync through the store's change feed, not the launch rule.
        try #require(await sync.isRunning)
        try await fixture.superFavorites.add(Self.topic, account: "Alice", at: Self.start)
        for _ in 0..<1000 where fixture.cloudSuperFavorites() == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(fixture.cloudSuperFavorites() == [Self.favorite()])
    }
}
