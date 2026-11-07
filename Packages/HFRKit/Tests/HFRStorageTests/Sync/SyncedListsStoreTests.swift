import Foundation
import HFRModels
import Synchronization
import Testing
@testable import HFRStorage

/// The list and reading-position sync of LOT-172 part 2 (ADR 0013 §3, Amendment 2) on the in-memory cloud store.
/// Events are handed to the store one by one, as `run()` would.
@Suite(.timeLimit(.minutes(1))) struct SyncedListsStoreTests {
    static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    static let topic = TopicID(category: .forum(13), topic: 28563)
    static let other = TopicID(category: .forum(13), topic: 100)
    static let superKey = "superfavorites.alice"
    static let smileyKey = "smileyfavorites.alice"
    static let positionsKey = "positions.alice"

    /// A settable clock.
    final class Clock: Sendable {
        private let current = Mutex(SyncedListsStoreTests.start)
        var now: Date { current.withLock { $0 } }
        func advance(seconds: Double) { current.withLock { $0 = $0.addingTimeInterval(seconds) } }
    }

    /// A positions persistence whose saves can be refused.
    final class FlakyPositionPersistence: ReadingPositionPersistence, @unchecked Sendable {
        // Tests drive one store from one task: no concurrent access.
        var failsToSave = false
        private var document: ReadingPositionDocument?

        func load() throws -> ReadingPositionDocument? { document }

        func save(_ document: ReadingPositionDocument) throws {
            if failsToSave { throw SmallStoreTestFailure() }
            self.document = document
        }

        func quarantineUnreadableData() throws { document = nil }
    }

    struct Fixture {
        let sync: SyncedListsStore
        let cloud: InMemorySyncedKeyValueStore
        let pseudoLists: PseudoListStore
        let superFavorites: SuperFavoritesStore
        let superFavoritePersistence: FailingSmallStorePersistence<SuperFavoritesDocument>
        let smileyFavorites: AppSmileyFavoritesStore
        let positions: ReadingPositionStore
        let positionPersistence: FlakyPositionPersistence
        let deviceState: FailingSmallStorePersistence<SyncedListsDeviceState>
        let clock: Clock

        /// The sync the app would build at its next launch, over the same stores, cloud and device file.
        func relaunched() async -> SyncedListsStore {
            let sync = SyncedListsStore(
                cloud: cloud, pseudoLists: pseudoLists, superFavorites: superFavorites, smileyFavorites: smileyFavorites,
                positions: positions, deviceState: deviceState, accounts: { ["Alice"] }, clock: { clock.now },
                sleep: { _ in }
            )
            await sync.start()
            return sync
        }

        /// Another device's change reaches this one.
        func receive(_ updates: [String: SyncedValue?]) async {
            let change = SyncedStoreChange(reason: .serverChange, keys: Array(updates.keys))
            cloud.receive(change, updates: updates)
            await sync.handle(.cloud(change))
        }

        /// The system switches the Apple ID (its store's content replaced by `values`), then the sync is told.
        func switchAppleID(to identity: String?, values: [String: SyncedValue?] = [:]) async {
            let change = SyncedStoreChange(reason: .accountChange)
            cloud.receive(change, updates: values, identity: .some(identity))
            await sync.handle(.cloud(change))
        }

        func cloudSuperFavorites() -> [SuperFavorite]? {
            cloud.value(forKey: SyncedListsStoreTests.superKey).flatMap { SyncedListEnvelope<SuperFavorite>($0)?.items }
        }

        func cloudPositions() -> [ReadingPositionRecord]? {
            cloud.value(forKey: SyncedListsStoreTests.positionsKey)
                .flatMap { SyncedListEnvelope<ReadingPositionRecord>($0)?.items }
        }

        func quarantine() -> [String: SyncQuarantineEntry] {
            deviceState.saved?.quarantine ?? [:]
        }
    }

    /// A device that already synced for `owner`, unless the test gives another state.
    static func make(
        identity: String? = "apple-1",
        owner: String? = "apple-1",
        cloud: [String: SyncedValue] = [:],
        deviceState: SyncedListsDeviceState? = nil
    ) async -> Fixture {
        let clock = Clock()
        let cloudStore = InMemorySyncedKeyValueStore(cloud, identity: identity)
        let superFavoritePersistence = FailingSmallStorePersistence<SuperFavoritesDocument>()
        let pseudoLists = PseudoListStore(persistence: InMemoryPseudoListPersistence())
        let superFavorites = SuperFavoritesStore(persistence: superFavoritePersistence)
        let smileyFavorites = AppSmileyFavoritesStore(persistence: InMemorySmallStorePersistence<AppSmileyFavoritesDocument>())
        let positionPersistence = FlakyPositionPersistence()
        let positions = ReadingPositionStore(persistence: positionPersistence)
        let persistence = FailingSmallStorePersistence(deviceState ?? SyncedListsDeviceState(owner: owner))
        let sync = SyncedListsStore(
            cloud: cloudStore, pseudoLists: pseudoLists, superFavorites: superFavorites, smileyFavorites: smileyFavorites,
            positions: positions, deviceState: persistence, accounts: { ["Alice"] }, clock: { clock.now },
            sleep: { _ in }
        )
        await sync.start()
        return Fixture(
            sync: sync, cloud: cloudStore, pseudoLists: pseudoLists, superFavorites: superFavorites,
            superFavoritePersistence: superFavoritePersistence, smileyFavorites: smileyFavorites, positions: positions,
            positionPersistence: positionPersistence, deviceState: persistence, clock: clock
        )
    }

    static func favorite(_ topic: TopicID = topic, at seconds: Double = 0) -> SuperFavorite {
        SuperFavorite(topic: topic, addedAt: start.addingTimeInterval(seconds))
    }

    static func position(page: Int, message: Int? = nil, at seconds: Double) -> ReadingPosition {
        ReadingPosition(page: page, messageNumber: message, updatedAt: start.addingTimeInterval(seconds))
    }

    static func envelope<Item: Codable & Hashable>(_ items: [Item]) -> SyncedValue {
        SyncedListEnvelope(items: items).value
    }

    // MARK: Lists

    @Test func aLocalAddIsPushedWholeAndStampsTheSchema() async throws {
        let fixture = await Self.make()
        try await fixture.superFavorites.add(Self.topic, account: "Alice", at: Self.start)
        await fixture.sync.handle(.listsChanged)
        #expect(fixture.cloudSuperFavorites() == [Self.favorite()])
        #expect(fixture.cloud.value(forKey: SyncedSettingsStore.schemaVersionKey) == .int(1))
    }

    @Test func removingTheLastItemPushesAnEmptyList() async throws {
        let fixture = await Self.make(cloud: [Self.superKey: Self.envelope([Self.favorite()])])
        #expect(await fixture.superFavorites.favorites(for: "Alice") == [Self.favorite()])
        try await fixture.superFavorites.remove(Self.topic, account: "Alice")
        await fixture.sync.handle(.listsChanged)
        #expect(fixture.cloudSuperFavorites() == [])
    }

    @Test func aServerChangeReplacesTheLocalListAndNothingIsPushedBack() async throws {
        let fixture = await Self.make()
        try await fixture.superFavorites.add(Self.other, account: "Alice", at: Self.start)
        await fixture.sync.handle(.listsChanged)
        // Another device's bytes, in a layout this one never writes: a push back would change them.
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        encoder.dateEncodingStrategy = .secondsSince1970
        let remote = SyncedValue.data(try encoder.encode(SyncedListEnvelope(items: [Self.favorite()])))
        #expect(remote != Self.envelope([Self.favorite()]))
        await fixture.receive([Self.superKey: remote])
        #expect(await fixture.superFavorites.favorites(for: "Alice") == [Self.favorite()])
        await fixture.sync.handle(.listsChanged)
        #expect(fixture.cloud.value(forKey: Self.superKey) == remote)
    }

    @Test func aServerChangeNeverOverwritesALocalChangeStillQueued() async throws {
        let fixture = await Self.make(cloud: [Self.superKey: Self.envelope([Self.favorite()])])
        try await fixture.superFavorites.add(Self.other, account: "Alice", at: Self.start)
        // Another device's list arrives before this device handled its own add.
        await fixture.receive([Self.superKey: Self.envelope([Self.favorite(Self.topic, at: 5)])])
        #expect(fixture.cloudSuperFavorites()?.map(\.topic) == [Self.other, Self.topic])
        #expect(await fixture.superFavorites.favorites(for: "Alice").count == 2)
    }

    @Test func aListRefusedForQuotaIsNeverReplacedByTheOlderCloudList() async throws {
        let fixture = await Self.make(cloud: [Self.superKey: Self.envelope([Self.favorite()])])
        try await fixture.superFavorites.add(Self.other, account: "Alice", at: Self.start)
        await fixture.sync.handle(.listsChanged)
        // The store refused the push and kept its older value.
        fixture.cloud.set(Self.envelope([Self.favorite()]), forKey: Self.superKey)
        await fixture.sync.handle(.cloud(SyncedStoreChange(reason: .quotaViolation, keys: [Self.superKey])))
        await fixture.sync.handle(.cloud(SyncedStoreChange(reason: .initialSync)))
        #expect(await fixture.superFavorites.favorites(for: "Alice").count == 2)
        #expect(fixture.cloudSuperFavorites()?.count == 2)
    }

    @Test func aRefusalReachingAPausedSyncIsMarkedBeforeItsRecovery() async throws {
        let fixture = await Self.make(cloud: [Self.superKey: Self.envelope([Self.favorite()])])
        try await fixture.superFavorites.add(Self.other, account: "Alice", at: Self.start)
        // The push leaves, but its digest cannot be saved: the sync pauses.
        fixture.deviceState.failsToSave = true
        await fixture.sync.handle(.listsChanged)
        // The store refused the push and kept its older value; the device file can be saved again.
        fixture.cloud.set(Self.envelope([Self.favorite()]), forKey: Self.superKey)
        fixture.deviceState.failsToSave = false
        await fixture.sync.handle(.cloud(SyncedStoreChange(reason: .quotaViolation, keys: [Self.superKey])))
        #expect(await fixture.superFavorites.favorites(for: "Alice").count == 2)
        #expect(fixture.cloudSuperFavorites()?.count == 2)
    }

    @Test func anUnchangedListNeverOverwritesAnotherDevicesPendingChange() async throws {
        let fixture = await Self.make(cloud: [Self.superKey: Self.envelope([Self.favorite()])])
        // Another device's list landed in the store; its notification has not been handled yet.
        fixture.cloud.set(Self.envelope([Self.favorite(Self.other)]), forKey: Self.superKey)
        try await fixture.pseudoLists.allow("Friend")
        await fixture.sync.handle(.listsChanged)
        #expect(fixture.cloudSuperFavorites() == [Self.favorite(Self.other)])
    }

    @Test func theInitialSyncRuleCloudWinsAndSeedsWhatTheCloudLacks() async throws {
        // Lists made before any Apple ID signed in: the first sign-in meets a cloud that has one of them.
        let fixture = await Self.make(identity: nil, owner: nil)
        try await fixture.superFavorites.add(Self.topic, account: "Alice", at: Self.start)
        let url = try #require(URL(string: "https://example.invalid/a.gif"))
        try await fixture.smileyFavorites.add(code: "[:a]", url: url, account: "Alice")
        await fixture.switchAppleID(to: "apple-1", values: [Self.superKey: Self.envelope([Self.favorite(Self.other)])])
        #expect(await fixture.superFavorites.favorites(for: "Alice") == [Self.favorite(Self.other)])
        #expect(fixture.cloud.value(forKey: Self.smileyKey) != nil)
    }

    @Test func aLocalChangeQueuedBehindAnotherEventIsPushedNotReplaced() async throws {
        let fixture = await Self.make(cloud: [Self.superKey: Self.envelope([Self.favorite(Self.other)])])
        try await fixture.superFavorites.add(Self.topic, account: "Alice", at: Self.start)
        // The add's signal is still queued when an account-list event runs the initial-sync rule.
        await fixture.sync.handle(.accountsChanged)
        await fixture.sync.handle(.listsChanged)
        #expect(fixture.cloudSuperFavorites()?.map(\.topic) == [Self.other, Self.topic])
    }

    @Test func aFirstSignInSeedsTheCloudWithTheDeviceListsButNotEmptyOnes() async throws {
        let fixture = await Self.make(identity: nil, owner: nil)
        try await fixture.pseudoLists.allow("Friend")
        fixture.cloud.receive(SyncedStoreChange(reason: .accountChange), identity: .some("apple-1"))
        _ = await fixture.relaunched()
        #expect(fixture.cloud.value(forKey: SyncedListsStore.allowlistKey) != nil)
        #expect(fixture.cloud.value(forKey: Self.superKey) == nil)
        #expect(fixture.cloud.value(forKey: Self.positionsKey) == nil)
        #expect(fixture.quarantine().isEmpty)
    }

    @Test func anUnreadableCloudListIsNeitherAppliedNorOverwritten() async throws {
        let garbage = SyncedValue.data(Data("not json".utf8))
        let newer = SyncedValue.data(Data(#"{"items":[],"version":2}"#.utf8))
        for value in [garbage, newer, SyncedValue.string("x")] {
            let fixture = await Self.make()
            try await fixture.superFavorites.add(Self.topic, account: "Alice", at: Self.start)
            await fixture.receive([Self.superKey: value])
            #expect(await fixture.superFavorites.favorites(for: "Alice") == [Self.favorite()])
            try await fixture.superFavorites.add(Self.other, account: "Alice", at: Self.start)
            await fixture.sync.handle(.listsChanged)
            #expect(fixture.cloud.value(forKey: Self.superKey) == value)
        }
    }

    @Test func aNewerSchemaStopsEveryWrite() async throws {
        let fixture = await Self.make(cloud: [SyncedSettingsStore.schemaVersionKey: .int(2)])
        try await fixture.superFavorites.add(Self.topic, account: "Alice", at: Self.start)
        await fixture.sync.handle(.listsChanged)
        try await fixture.positions.advance(Self.topic, to: Self.position(page: 2, at: 0), account: "Alice")
        await fixture.sync.handle(.flushPositions)
        await fixture.sync.handle(.positionsChanged)
        await fixture.sync.handle(.flushPositions)
        #expect(fixture.cloud.value(forKey: Self.superKey) == nil)
        #expect(fixture.cloud.value(forKey: Self.positionsKey) == nil)
    }

    @Test func anAccountWhoseLongestKeyIsTooLongSyncsNoList() async throws {
        // `positions.` fits, `smileyfavorites.` does not: the account syncs none of its lists.
        let long = String(repeating: "x", count: 50)
        let fixture = await Self.make()
        let sync = SyncedListsStore(
            cloud: fixture.cloud, pseudoLists: fixture.pseudoLists, superFavorites: fixture.superFavorites,
            smileyFavorites: fixture.smileyFavorites, positions: fixture.positions, deviceState: fixture.deviceState,
            accounts: { [long] }, sleep: { _ in }
        )
        await sync.start()
        try await fixture.superFavorites.add(Self.topic, account: long, at: Self.start)
        try await fixture.positions.advance(Self.topic, to: Self.position(page: 2, at: 0), account: long)
        await sync.handle(.listsChanged)
        await sync.handle(.positionsChanged)
        await sync.handle(.flushPositions)
        #expect(!fixture.cloud.values.keys.contains { $0.hasPrefix("positions.") || $0.hasPrefix("superfavorites.") })
        #expect(fixture.cloud.values.keys.allSatisfy { $0.utf8.count <= SyncedListsStore.maximumKeyLength })
        #expect(await sync.unsyncedAccounts == [long])
    }

    @Test func quotaViolationsAreReportedForListKeysOnly() async {
        let fixture = await Self.make()
        await fixture.sync.handle(.cloud(SyncedStoreChange(reason: .quotaViolation, keys: [Self.superKey, "display_sig"])))
        #expect(await fixture.sync.quotaViolations == [Self.superKey])
    }
}
