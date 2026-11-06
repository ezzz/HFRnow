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

    struct Fixture {
        let sync: SyncedListsStore
        let cloud: InMemorySyncedKeyValueStore
        let pseudoLists: PseudoListStore
        let superFavorites: SuperFavoritesStore
        let superFavoritePersistence: FailingSmallStorePersistence<SuperFavoritesDocument>
        let smileyFavorites: AppSmileyFavoritesStore
        let positions: ReadingPositionStore
        let deviceState: InMemorySmallStorePersistence<SyncedListsDeviceState>
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
            (try? deviceState.load())??.quarantine ?? [:]
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
        let positions = ReadingPositionStore(persistence: InMemoryReadingPositionPersistence())
        let persistence = InMemorySmallStorePersistence(deviceState ?? SyncedListsDeviceState(owner: owner))
        let sync = SyncedListsStore(
            cloud: cloudStore, pseudoLists: pseudoLists, superFavorites: superFavorites, smileyFavorites: smileyFavorites,
            positions: positions, deviceState: persistence, accounts: { ["Alice"] }, clock: { clock.now },
            sleep: { _ in }
        )
        await sync.start()
        return Fixture(
            sync: sync, cloud: cloudStore, pseudoLists: pseudoLists, superFavorites: superFavorites,
            superFavoritePersistence: superFavoritePersistence, smileyFavorites: smileyFavorites, positions: positions,
            deviceState: persistence, clock: clock
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

    @Test func anUnchangedListNeverOverwritesAnotherDevicesPendingChange() async throws {
        let fixture = await Self.make(cloud: [Self.superKey: Self.envelope([Self.favorite()])])
        // Another device's list landed in the store; its notification has not been handled yet.
        fixture.cloud.set(Self.envelope([Self.favorite(Self.other)]), forKey: Self.superKey)
        try await fixture.pseudoLists.allow("Friend")
        await fixture.sync.handle(.listsChanged)
        #expect(fixture.cloudSuperFavorites() == [Self.favorite(Self.other)])
    }

    @Test func theInitialSyncRuleCloudWinsAndSeedsWhatTheCloudLacks() async throws {
        let fixture = await Self.make(owner: nil, cloud: [Self.superKey: Self.envelope([Self.favorite(Self.other)])])
        // Owner recorded by the first launch; now give the device lists the cloud does or does not have.
        try await fixture.superFavorites.add(Self.topic, account: "Alice", at: Self.start)
        try await fixture.smileyFavorites.add(code: "[:a]", url: URL(string: "https://example.invalid/a.gif")!, account: "Alice")
        await fixture.sync.handle(.cloud(SyncedStoreChange(reason: .initialSync)))
        #expect(await fixture.superFavorites.favorites(for: "Alice") == [Self.favorite(Self.other)])
        #expect(fixture.cloud.value(forKey: Self.smileyKey) != nil)
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

    @Test func aKeyLongerThanAppleAllowsIsNotSyncedAndReported() async throws {
        let long = String(repeating: "x", count: 60)
        let fixture = await Self.make()
        let sync = SyncedListsStore(
            cloud: fixture.cloud, pseudoLists: fixture.pseudoLists, superFavorites: fixture.superFavorites,
            smileyFavorites: fixture.smileyFavorites, positions: fixture.positions, deviceState: fixture.deviceState,
            accounts: { [long] }, sleep: { _ in }
        )
        await sync.start()
        try await fixture.superFavorites.add(Self.topic, account: long, at: Self.start)
        await sync.handle(.listsChanged)
        #expect(fixture.cloud.values.keys.allSatisfy { $0.utf8.count <= SyncedListsStore.maximumKeyLength })
        #expect(await sync.unsyncedAccounts == [long])
    }

    @Test func quotaViolationsAreReportedForListKeysOnly() async {
        let fixture = await Self.make()
        await fixture.sync.handle(.cloud(SyncedStoreChange(reason: .quotaViolation, keys: [Self.superKey, "display_sig"])))
        #expect(await fixture.sync.quotaViolations == [Self.superKey])
    }

    // MARK: Reading positions

    @Test func aPositionIsPushedAfterTheDelayOrAFlushNotBefore() async throws {
        let fixture = await Self.make()
        try await fixture.positions.advance(Self.topic, to: Self.position(page: 2, at: 0), account: "Alice")
        await fixture.sync.handle(.positionsChanged)
        await fixture.sync.handle(.positionsChanged)
        #expect(fixture.cloudPositions() == nil)
        await fixture.sync.handle(.positionsDue(1))
        #expect(fixture.cloudPositions() == nil)
        await fixture.sync.handle(.positionsDue(2))
        #expect(fixture.cloudPositions()?.map(\.topic) == [Self.topic])

        try await fixture.positions.advance(Self.topic, to: Self.position(page: 3, at: 10), account: "Alice")
        await fixture.sync.handle(.positionsChanged)
        await fixture.sync.handle(.flushPositions)
        #expect(fixture.cloudPositions()?.first?.position.page == 3)
    }

    @Test func theNewestPositionWinsEvenWhenItIsBehindAndNothingPingPongs() async throws {
        let fixture = await Self.make()
        try await fixture.positions.advance(Self.topic, to: Self.position(page: 5, at: 0), account: "Alice")
        let remote = Self.envelope([ReadingPositionRecord(topic: Self.topic, position: Self.position(page: 2, at: 10))])
        await fixture.receive([Self.positionsKey: remote])
        #expect(await fixture.positions.position(of: Self.topic, account: "Alice")?.page == 2)
        await fixture.sync.handle(.positionsChanged)
        await fixture.sync.handle(.flushPositions)
        #expect(fixture.cloud.value(forKey: Self.positionsKey) == remote)
    }

    @Test func onEqualDatesThePositionAheadWins() async throws {
        let fixture = await Self.make()
        try await fixture.positions.advance(Self.topic, to: Self.position(page: 2, at: 0), account: "Alice")
        let remote = Self.envelope([ReadingPositionRecord(topic: Self.topic, position: Self.position(page: 4, at: 0))])
        await fixture.receive([Self.positionsKey: remote])
        #expect(await fixture.positions.position(of: Self.topic, account: "Alice")?.page == 4)
        let behind = Self.envelope([ReadingPositionRecord(topic: Self.topic, position: Self.position(page: 1, at: 0))])
        await fixture.receive([Self.positionsKey: behind])
        #expect(await fixture.positions.position(of: Self.topic, account: "Alice")?.page == 4)
    }

    @Test func theSamePlaceWithAnotherDateIsNeverPushedBack() async throws {
        let fixture = await Self.make()
        try await fixture.positions.advance(Self.topic, to: Self.position(page: 3, at: 0), account: "Alice")
        // Another device recorded the same place later, its clock a day ahead: taken as recorded, nothing to push.
        let remote = Self.envelope([ReadingPositionRecord(topic: Self.topic, position: Self.position(page: 3, at: 86_400))])
        await fixture.receive([Self.positionsKey: remote])
        #expect(await fixture.positions.position(of: Self.topic, account: "Alice")?.updatedAt
            == Self.start.addingTimeInterval(86_400))
        await fixture.sync.handle(.positionsChanged)
        await fixture.sync.handle(.flushPositions)
        #expect(fixture.cloud.value(forKey: Self.positionsKey) == remote)
    }

    @Test func aPushKeepsThePositionsOnlyTheCloudHas() async throws {
        let remote = [ReadingPositionRecord(topic: Self.other, position: Self.position(page: 7, at: 5))]
        let fixture = await Self.make(cloud: [Self.positionsKey: Self.envelope(remote)])
        try await fixture.positions.advance(Self.topic, to: Self.position(page: 2, at: 10), account: "Alice")
        await fixture.sync.handle(.positionsChanged)
        await fixture.sync.handle(.flushPositions)
        #expect(Set(fixture.cloudPositions()?.map(\.topic) ?? []) == [Self.topic, Self.other])
    }

    @Test func onlyTheNewestPositionsReachTheCloud() async throws {
        let fixture = await Self.make()
        for number in 1...250 {
            let topic = TopicID(category: .forum(13), topic: number)
            try await fixture.positions.advance(topic, to: Self.position(page: 1, at: Double(number)), account: "Alice")
        }
        await fixture.sync.handle(.positionsChanged)
        await fixture.sync.handle(.flushPositions)
        let pushed = try #require(fixture.cloudPositions())
        #expect(pushed.count == SyncedListsStore.positionsLimit)
        #expect(Set(pushed.map(\.topic.topic)) == Set(51...250))
    }
}
