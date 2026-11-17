import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// The rehost upload history through iCloud (#966): Apple ID changes, failures and other formats.
extension SyncedListsStoreRehostTests {
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

    @Test func aHistoryThatCouldNotBeSetAsideNeverReachesTheNewAppleID() async throws {
        let device = await Self.device(images: Self.images(1...2))
        device.historyPersistence.failsToSave = true
        await device.switchAppleID(to: "apple-2")
        #expect(await device.history.images() == Self.images(1...2))
        await device.sync.handle(.listsChanged)
        await device.sync.handle(.cloud(SyncedStoreChange(reason: .initialSync)))
        #expect(device.cloud.value(forKey: Self.key) == nil)
    }

    @Test func aSetAsideHistoryNeverReplacesOneAlreadyThere() async throws {
        let device = await Self.device(images: Self.images(1...2))
        await device.switchAppleID(to: "apple-2")
        try await device.history.add(Self.image(7))
        // The first Apple ID's history is due back while this device already holds another one.
        let setAside = device.deviceState.saved?.quarantine["apple-1"]?.values[Self.key]
        #expect(setAside != nil)
        device.cloud.receive(SyncedStoreChange(reason: .accountChange), identity: .some("apple-1"))
        await device.sync.restore(for: "apple-1")
        #expect(await device.history.images() == [Self.image(7)])
        #expect(device.deviceState.saved?.quarantine["apple-1"]?.values[Self.key] == setAside)
    }

    @Test func aRefusedHistoryKeepsNoDigest() async throws {
        let device = await Self.device(images: Self.images(1...2))
        await device.sync.handle(.cloud(SyncedStoreChange(reason: .quotaViolation, keys: [Self.key])))
        #expect(await device.sync.quotaViolations == [Self.key])
        #expect(device.deviceState.saved?.synced[Self.key] == nil)
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
