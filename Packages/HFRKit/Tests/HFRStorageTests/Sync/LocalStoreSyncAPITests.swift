import Foundation
import HFRModels
import Testing
@testable import HFRStorage

/// What the four local stores give the iCloud sync (LOT-172 part 2): whole-list replace, the positions merge, the
/// keys they hold and a signal after each saved change.
@Suite(.timeLimit(.minutes(1))) struct LocalStoreSyncAPITests {
    static let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
    static let first = TopicID(category: .forum(13), topic: 1)
    static let second = TopicID(category: .forum(13), topic: 2)

    /// Whether a signal is waiting on `stream` (the stream keeps the newest one). A false answer ends the stream: the
    /// waiting iteration is cancelled.
    static func signalled(_ stream: AsyncStream<Void>) async -> Bool {
        let probe = Task { () -> Bool in
            var iterator = stream.makeAsyncIterator()
            return await iterator.next() != nil
        }
        // A pending signal is delivered at once; none leaves the probe waiting, so it is cancelled.
        try? await Task.sleep(for: .milliseconds(20))
        probe.cancel()
        return await probe.value
    }

    @Test func superFavoritesReplaceNormalisesAndSignalsOnlyARealChange() async throws {
        let store = SuperFavoritesStore(persistence: InMemorySmallStorePersistence<SuperFavoritesDocument>())
        let changes = await store.changes()
        let invalid = TopicID(category: .forum(13), topic: 0)
        let list = [
            SuperFavorite(topic: Self.second, addedAt: Self.start), SuperFavorite(topic: Self.first, addedAt: Self.start),
            SuperFavorite(topic: Self.second, addedAt: Self.start.addingTimeInterval(9)),
            SuperFavorite(topic: invalid, addedAt: Self.start)
        ]
        #expect(try await store.replace(list, account: "Alice"))
        #expect(await store.favorites(for: "alice").map(\.topic) == [Self.first, Self.second])
        #expect(await store.favorites(for: "alice").last?.addedAt == Self.start)
        #expect(await store.accountKeys() == ["alice"])
        #expect(await Self.signalled(changes))
        #expect(try await store.replace(list, account: "ALICE") == false)
        #expect(await Self.signalled(changes) == false)
        #expect(try await store.replace([], account: "Alice"))
        #expect(await store.accountKeys().isEmpty)
    }

    @Test func smileyFavoritesReplaceDropsBlankCodesAndSignals() async throws {
        let store = AppSmileyFavoritesStore(persistence: InMemorySmallStorePersistence<AppSmileyFavoritesDocument>())
        let changes = await store.changes()
        let url = try #require(URL(string: "https://example.invalid/a.gif"))
        let list = [
            AppSmileyFavorite(code: "[:b]", url: url, addedAt: Self.start.addingTimeInterval(5)),
            AppSmileyFavorite(code: " ", url: url, addedAt: Self.start),
            AppSmileyFavorite(code: "[:a]", url: url, addedAt: Self.start)
        ]
        #expect(try await store.replace(list, account: "Alice"))
        #expect(await store.favorites(for: "Alice").map(\.code) == ["[:a]", "[:b]"])
        #expect(await Self.signalled(changes))
        try await store.add(code: "[:c]", url: url, account: "Alice", at: Self.start.addingTimeInterval(9))
        #expect(await Self.signalled(changes))
    }

    @Test func allowlistReplaceKeepsAliasesAndSignalsTheAllowlistOnly() async throws {
        let store = PseudoListStore(persistence: InMemoryPseudoListPersistence())
        let blocklistProbe = await store.allowlistChanges()
        try await store.block("Spammer", account: "Alice")
        #expect(await Self.signalled(blocklistProbe) == false)
        let changes = await store.allowlistChanges()
        let entries = [
            PseudoListEntry(pseudo: "Friend", alias: "F", mode: 2), PseudoListEntry(pseudo: "FRIEND"),
            PseudoListEntry(pseudo: " "), PseudoListEntry(pseudo: "Other")
        ]
        #expect(try await store.replaceAllowlist(with: entries))
        #expect(await store.allowlist() == [PseudoListEntry(pseudo: "Friend", alias: "F", mode: 2), PseudoListEntry(pseudo: "Other")])
        #expect(await Self.signalled(changes))
        #expect(try await store.replaceAllowlist(with: entries) == false)
        #expect(await store.blocklist(for: "Alice").map(\.pseudo) == ["Spammer"])
    }

    @Test func positionsMergeKeepsTheNewestWhateverThePageAndTheLimit() async throws {
        let store = ReadingPositionStore(persistence: InMemoryReadingPositionPersistence(), limitPerAccount: 2)
        let changes = await store.changes()
        let third = TopicID(category: .forum(13), topic: 3)
        try await store.advance(Self.first, to: ReadingPosition(page: 5, updatedAt: Self.start), account: "Alice")
        #expect(await Self.signalled(changes))
        let incoming = [
            ReadingPositionRecord(topic: Self.first, position: ReadingPosition(page: 2, updatedAt: Self.start.addingTimeInterval(1))),
            ReadingPositionRecord(topic: Self.second, position: ReadingPosition(page: 1, updatedAt: Self.start.addingTimeInterval(3))),
            ReadingPositionRecord(topic: third, position: ReadingPosition(page: 1, updatedAt: Self.start.addingTimeInterval(-5))),
            ReadingPositionRecord(topic: third, position: ReadingPosition(page: 0, updatedAt: Self.start.addingTimeInterval(9)))
        ]
        #expect(try await store.merge(incoming, account: "Alice"))
        #expect(await store.position(of: Self.first, account: "Alice")?.page == 2)
        #expect(await store.records(for: "Alice").map(\.topic) == [Self.second, Self.first])
        #expect(await store.accounts() == ["Alice"])
        #expect(await Self.signalled(changes))
        #expect(try await store.merge(incoming, account: "Alice") == false)
    }

    @Test func positionsMergeOnEqualDatesKeepsThePositionAhead() async throws {
        let store = ReadingPositionStore(persistence: InMemoryReadingPositionPersistence())
        try await store.advance(Self.first, to: ReadingPosition(page: 3, updatedAt: Self.start), account: "Alice")
        let behind = ReadingPositionRecord(topic: Self.first, position: ReadingPosition(page: 1, updatedAt: Self.start))
        #expect(try await store.merge([behind], account: "Alice") == false)
        let ahead = ReadingPositionRecord(topic: Self.first, position: ReadingPosition(page: 4, updatedAt: Self.start))
        #expect(try await store.merge([ahead], account: "Alice"))
        #expect(await store.position(of: Self.first, account: "Alice")?.page == 4)
    }
}
