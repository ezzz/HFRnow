import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// The rehost upload history through iCloud (#966, ADR 0013 Amendment 4): the 100 newest uploads, merged by id with
/// their removals, at activation and on every change, with the Apple ID rules of the other lists.
@Suite(.timeLimit(.minutes(1))) struct SyncedListsStoreRehostTests {
    static let key = SyncedListsStore.rehostHistoryKey

    /// One device: its sync, its iCloud store, its upload history.
    struct Device {
        let sync: SyncedListsStore
        let cloud: InMemorySyncedKeyValueStore
        let history: RehostUploadHistoryStore
        let historyPersistence: FailingSmallStorePersistence<RehostUploadHistoryDocument>
        let deviceState: FailingSmallStorePersistence<SyncedListsDeviceState>

        /// The history the cloud holds, nil when it holds none.
        func cloudHistory() -> RehostHistoryEnvelope? {
            cloud.value(forKey: SyncedListsStoreRehostTests.key).flatMap(RehostHistoryEnvelope.init)
        }

        /// Another device's value reaches this one.
        func receive(_ value: SyncedValue?) async {
            let change = SyncedStoreChange(reason: .serverChange, keys: [SyncedListsStoreRehostTests.key])
            cloud.receive(change, updates: [SyncedListsStoreRehostTests.key: value])
            await sync.handle(.cloud(change))
        }

        /// The system switches the Apple ID (its store's content replaced by `values`), then the sync is told.
        func switchAppleID(to identity: String?, values: [String: SyncedValue?] = [:]) async {
            let change = SyncedStoreChange(reason: .accountChange)
            cloud.receive(change, updates: values, identity: .some(identity))
            await sync.handle(.cloud(change))
        }

        /// Adds an upload here, as the composer does, and lets the sync see it.
        func upload(_ image: RehostedImage) async throws {
            try await history.add(image)
            await sync.handle(.listsChanged)
        }

        /// Removes an upload here, as the composer does, and lets the sync see it.
        func remove(_ image: RehostedImage) async throws {
            try await history.remove(id: image.id)
            await sync.handle(.listsChanged)
        }
    }

    /// A device whose history holds `images` (newest first), started with the sync.
    static func device(
        identity: String? = "apple-1",
        owner: String? = "apple-1",
        cloud: [String: SyncedValue] = [:],
        images: [RehostedImage] = [],
        syncsHistory: Bool = true
    ) async -> Device {
        let cloudStore = InMemorySyncedKeyValueStore(cloud, identity: identity)
        let historyPersistence = FailingSmallStorePersistence(RehostUploadHistoryDocument(images: images))
        let history = RehostUploadHistoryStore(persistence: historyPersistence, clock: { SmallStoreTestSupport.date(10_000) })
        let deviceState = FailingSmallStorePersistence(SyncedListsDeviceState(owner: owner))
        let sync = SyncedListsStore(
            cloud: cloudStore,
            pseudoLists: PseudoListStore(persistence: InMemoryPseudoListPersistence()),
            superFavorites: SuperFavoritesStore(persistence: InMemorySmallStorePersistence<SuperFavoritesDocument>()),
            smileyFavorites: AppSmileyFavoritesStore(persistence: InMemorySmallStorePersistence<AppSmileyFavoritesDocument>()),
            positions: ReadingPositionStore(persistence: InMemoryReadingPositionPersistence()),
            rehostHistory: syncsHistory ? history : nil,
            deviceState: deviceState,
            accounts: { [] },
            clock: { SmallStoreTestSupport.date(10_000) },
            sleep: { _ in }
        )
        await sync.start()
        return Device(
            sync: sync, cloud: cloudStore, history: history, historyPersistence: historyPersistence, deviceState: deviceState
        )
    }

    static func image(_ number: Int) -> RehostedImage {
        RehostedImage(
            // A literal URL with a number in it always parses.
            fullURL: URL(string: "https://img.example/\(number).png") ?? URL(filePath: "/"),
            miniURL: URL(string: "https://img.example/\(number).th.png"),
            // Fractional seconds, as `Date()` gives: the dates that seconds since 1970 would not read back.
            uploadedAt: SmallStoreTestSupport.date(Double(number) + 0.123_456_7)
        )
    }

    /// `count` uploads, the newest (highest number) first.
    static func images(_ numbers: ClosedRange<Int>) -> [RehostedImage] {
        numbers.reversed().map(image)
    }

    // MARK: Activation

    @Test func turningSyncOnPushesTheHundredNewestOfTheLocalHistory() async throws {
        let device = await Self.device(owner: nil, images: Self.images(1...120))
        let cloud = try #require(device.cloudHistory())
        #expect(cloud.items == Self.images(21...120))
        #expect(cloud.version == 1)
        // The whole history stays on the device.
        #expect(await device.history.images().count == 120)
        #expect(device.cloud.value(forKey: SyncedSettingsStore.schemaVersionKey) == .int(SyncedSettingsStore.schemaVersion))
    }

    @Test func turningSyncOnMergesTheLocalHistoryIntoTheCloudOne() async throws {
        let other = RehostHistoryEnvelope(RehostUploadHistoryDocument(images: Self.images(5...6)), limit: 100)
        let device = await Self.device(owner: nil, cloud: [Self.key: other.value], images: Self.images(1...2))
        #expect(device.cloudHistory()?.items == [6, 5, 2, 1].map(Self.image))
        #expect(await device.history.images() == [6, 5, 2, 1].map(Self.image))
    }

    @Test func signingInLaterPushesTheHistory() async throws {
        let device = await Self.device(identity: nil, owner: nil, images: Self.images(1...2))
        #expect(device.cloud.values.isEmpty)
        await device.switchAppleID(to: "apple-1")
        #expect(device.cloudHistory()?.items == Self.images(1...2))
    }

    @Test func withoutSyncNothingLeavesTheDevice() async throws {
        let signedOut = await Self.device(identity: nil, owner: nil, images: Self.images(1...2))
        try await signedOut.upload(Self.image(3))
        #expect(signedOut.cloud.values.isEmpty)

        let notWired = await Self.device(owner: nil, images: Self.images(1...2), syncsHistory: false)
        try await notWired.upload(Self.image(3))
        #expect(notWired.cloud.value(forKey: Self.key) == nil)
    }

    @Test func anEmptyHistoryWritesNoKey() async throws {
        let device = await Self.device(owner: nil)
        #expect(device.cloud.value(forKey: Self.key) == nil)
        #expect(device.historyPersistence.saveCount == 0)
    }

    // MARK: Two devices

    @Test func addsMadeOnTwoDevicesBothSurvive() async throws {
        let phone = await Self.device()
        let tablet = await Self.device()
        try await phone.upload(Self.image(1))
        try await tablet.upload(Self.image(2))
        // Each device pushed before it saw the other's add: the cloud kept the tablet's, last writer.
        await phone.receive(tablet.cloud.value(forKey: Self.key))
        #expect(await phone.history.images() == [2, 1].map(Self.image))
        #expect(phone.cloudHistory()?.items == [2, 1].map(Self.image))
        await tablet.receive(phone.cloud.value(forKey: Self.key))
        #expect(await tablet.history.images() == [2, 1].map(Self.image))
        // Converged: nothing more to push.
        let saves = tablet.historyPersistence.saveCount
        await tablet.receive(phone.cloud.value(forKey: Self.key))
        #expect(tablet.historyPersistence.saveCount == saves)
    }

    @Test func aRemovalOnOneDeviceRemovesTheUploadOnTheOtherAndIsNotUndone() async throws {
        let shared = RehostHistoryEnvelope(RehostUploadHistoryDocument(images: Self.images(1...2)), limit: 100).value
        let phone = await Self.device(cloud: [Self.key: shared], images: Self.images(1...2))
        let tablet = await Self.device(cloud: [Self.key: shared], images: Self.images(1...2))
        try await phone.remove(Self.image(1))
        #expect(phone.cloudHistory()?.items == [Self.image(2)])
        #expect(phone.cloudHistory()?.removals.map(\.id) == [Self.image(1).id])

        // The tablet uploads before it hears of the removal: its push still holds the removed upload.
        try await tablet.upload(Self.image(3))
        await tablet.receive(phone.cloud.value(forKey: Self.key))
        #expect(await tablet.history.images() == [3, 2].map(Self.image))
        await phone.receive(tablet.cloud.value(forKey: Self.key))
        #expect(await phone.history.images() == [3, 2].map(Self.image))
        #expect(phone.cloudHistory()?.items == [3, 2].map(Self.image))
    }

    @Test func aRemovalReachesAnUploadOlderThanTheCloudCopy() async throws {
        let phone = await Self.device(owner: nil, images: Self.images(1...150))
        let removal = RehostUploadRemoval(id: Self.image(3).id, removedAt: SmallStoreTestSupport.date(500))
        let incoming = RehostHistoryEnvelope(
            RehostUploadHistoryDocument(images: Self.images(51...150), removals: [removal]), limit: 100
        )
        await phone.receive(incoming.value)
        #expect(await phone.history.images().count == 149)
        #expect(await phone.history.images().contains(Self.image(3)) == false)
    }

    // MARK: Cap

    @Test func theCloudHoldsTheHundredNewestOfBothDevices() async throws {
        // The phone uploaded the even numbers up to 100, the tablet the odd ones up to 199.
        let phone = await Self.device(images: stride(from: 100, through: 2, by: -2).map(Self.image))
        let tablet = RehostHistoryEnvelope(
            RehostUploadHistoryDocument(images: stride(from: 199, through: 1, by: -2).map(Self.image)), limit: 100
        )
        await phone.receive(tablet.value)
        let cloud = try #require(phone.cloudHistory())
        #expect(cloud.items.count == 100)
        #expect(cloud.items == RehostUploadHistoryDocument.newestFirst(cloud.items))
        #expect(cloud.items.first == Self.image(199))
        // Every upload of both devices stays on the phone.
        #expect(await phone.history.images().count == 150)
    }

    @Test func removalsAreCappedToTheNewest() async throws {
        let removals = (1...150).map { RehostUploadRemoval(id: "gone-\($0)", removedAt: SmallStoreTestSupport.date(Double($0))) }
        let document = RehostUploadHistoryDocument().merging(images: [], removals: removals)
        #expect(document.removals.count == RehostUploadHistoryDocument.removalsLimit)
        #expect(document.removals.first?.id == "gone-150")
        #expect(document.removals.last?.id == "gone-51")
    }

    // MARK: Apple ID

    @Test func anotherAppleIDNeverReceivesTheHistoryAndItComesBackWithTheFirst() async throws {
        let device = await Self.device(images: Self.images(1...2))
        await device.sync.handle(.listsChanged)
        let otherCloud = RehostHistoryEnvelope(RehostUploadHistoryDocument(images: [Self.image(9)]), limit: 100).value

        await device.switchAppleID(to: "apple-2", values: [Self.key: otherCloud])
        #expect(await device.history.images() == [Self.image(9)])
        #expect(device.cloudHistory()?.items == [Self.image(9)])
        let quarantined = try #require(device.deviceState.saved?.quarantine["apple-1"]?.values[Self.key])
        #expect(RehostHistoryEnvelope(quarantined)?.items == Self.images(1...2))

        await device.switchAppleID(to: "apple-1", values: [:])
        #expect(await device.history.images() == Self.images(1...2))
        #expect(device.cloudHistory()?.items == Self.images(1...2))
        #expect(device.deviceState.saved?.quarantine["apple-1"] == nil)
    }

    @Test func theQuarantineKeepsTheWholeHistory() async throws {
        let device = await Self.device(images: Self.images(1...130))
        await device.switchAppleID(to: "apple-2")
        let quarantined = try #require(device.deviceState.saved?.quarantine["apple-1"]?.values[Self.key])
        #expect(RehostHistoryEnvelope(quarantined)?.items.count == 130)
        #expect(device.cloud.value(forKey: Self.key) == nil)
    }

    @Test func aSignOutKeepsTheHistoryAndPushesNothing() async throws {
        let device = await Self.device(images: Self.images(1...2))
        await device.switchAppleID(to: nil)
        try await device.upload(Self.image(3))
        #expect(await device.history.images() == Self.images(1...3))
        #expect(device.cloud.values.isEmpty)
        await device.switchAppleID(to: "apple-1")
        #expect(device.cloudHistory()?.items == Self.images(1...3))
    }

    // MARK: Failures and other formats

    @Test func aMergeThatCannotBeSavedPushesNothing() async throws {
        let device = await Self.device(images: [Self.image(1)])
        device.historyPersistence.failsToSave = true
        let incoming = RehostHistoryEnvelope(RehostUploadHistoryDocument(images: [Self.image(2)]), limit: 100).value
        await device.receive(incoming)
        #expect(device.cloud.value(forKey: Self.key) == incoming)
        #expect(await device.history.images() == [Self.image(1)])
    }

    @Test func aNewerCloudFormatIsNeitherAppliedNorOverwritten() async throws {
        let newer = SyncedValue.data(Data(#"{"version":2,"items":[],"removals":[],"albums":[]}"#.utf8))
        let device = await Self.device(cloud: [Self.key: newer], images: [Self.image(1)])
        try await device.upload(Self.image(2))
        #expect(device.cloud.value(forKey: Self.key) == newer)
        #expect(await device.history.images() == [2, 1].map(Self.image))
    }

    @Test func theHistoryKeyIsAListKeyAndNotLastWriterWins() {
        #expect(SyncedListsStore.isListKey(Self.key))
        #expect(!SyncedListsStore.usesDigest(Self.key))
        #expect(SyncedListsStore.Slot.rehostHistory.owns(Self.key))
        #expect(!SyncedListsStore.Slot.allowlist.owns(Self.key))
    }

    /// Seconds since 1970 keeps the ids but not the dates (LOT-064): a copy would never equal the device's own.
    @Test func aCloudItemReadsBackAsStored() throws {
        let images = (0..<500).reversed().map { index in
            RehostedImage(
                fullURL: URL(string: "https://img.example/\(index).png") ?? URL(filePath: "/"),
                uploadedAt: Date(timeIntervalSinceReferenceDate: 815_000_000 + Double(index) * 1.618_033_988_7)
            )
        }
        let value = RehostHistoryEnvelope(RehostUploadHistoryDocument(images: images), limit: .max).value
        #expect(try #require(RehostHistoryEnvelope(value)).items == images)
    }
}
