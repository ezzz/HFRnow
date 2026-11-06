import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// The reading positions in the list sync (LOT-172 part 2, ADR 0013 Amendment 2).
extension SyncedListsStoreTests {
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

        // The same place, recorded here again later: only the date differs, so nothing is pushed.
        try await fixture.positions.reset(Self.topic, to: Self.position(page: 3, at: 90_000), account: "Alice")
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

    @Test func aMergeThatCannotBeSavedPushesNothingOverTheCloud() async throws {
        let remote = Self.envelope([ReadingPositionRecord(topic: Self.other, position: Self.position(page: 7, at: 5))])
        let fixture = await Self.make()
        try await fixture.positions.advance(Self.topic, to: Self.position(page: 2, at: 10), account: "Alice")
        // Another device's positions landed; this device cannot save them.
        fixture.cloud.set(remote, forKey: Self.positionsKey)
        fixture.positionPersistence.failsToSave = true
        await fixture.sync.handle(.positionsChanged)
        await fixture.sync.handle(.flushPositions)
        #expect(fixture.cloud.value(forKey: Self.positionsKey) == remote)
    }

    @Test func runPushesAPositionAfterTheDelayAndEndsWhenCancelled() async throws {
        let fixture = await Self.make()
        let sync = SyncedListsStore(
            cloud: fixture.cloud, pseudoLists: fixture.pseudoLists, superFavorites: fixture.superFavorites,
            smileyFavorites: fixture.smileyFavorites, positions: fixture.positions, deviceState: fixture.deviceState,
            accounts: { ["Alice"] }, positionsDelay: .milliseconds(20)
        )
        let running = Task { await sync.run() }
        try await Task.sleep(for: .milliseconds(20))
        try await fixture.positions.advance(Self.topic, to: Self.position(page: 2, at: 0), account: "Alice")
        for _ in 0..<1000 where fixture.cloudPositions() == nil {
            try await Task.sleep(for: .milliseconds(5))
        }
        #expect(fixture.cloudPositions()?.map(\.topic) == [Self.topic])
        running.cancel()
        await running.value
    }
}
