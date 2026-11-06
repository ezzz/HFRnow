import Foundation
import HFRModels
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
        #expect(fixture.quarantine()["apple-1"]?.values.keys.sorted()
            == [SyncedListsStore.allowlistKey, "positions.Alice", Self.superKey])

        await fixture.switchAppleID(to: "apple-1", values: [:])
        #expect(await fixture.superFavorites.favorites(for: "Alice") == [Self.favorite()])
        #expect(await fixture.pseudoLists.allowlist().map(\.pseudo) == ["Friend"])
        #expect(await fixture.positions.position(of: Self.topic, account: "Alice")?.page == 2)
        #expect(fixture.quarantine()["apple-1"] == nil)
        #expect(fixture.quarantine()["apple-2"]?.values.keys.sorted() == [Self.superKey])
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
        try await fixture.superFavorites.add(Self.topic, account: "Alice", at: Self.start)
        for _ in 0..<1000 where fixture.cloudSuperFavorites() == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(fixture.cloudSuperFavorites() == [Self.favorite()])
    }
}
