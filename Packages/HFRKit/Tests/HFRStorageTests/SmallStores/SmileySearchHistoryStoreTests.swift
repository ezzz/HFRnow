import Foundation
import Testing
@testable import HFRStorage

/// Smiley search history: legacy rules of `SmileySearchService.swift:78-140`, at their boundaries.
@Suite struct SmileySearchHistoryStoreTests {
    private static func date(_ seconds: Double) -> Date { SmallStoreTestSupport.date(seconds) }

    /// A store already holding `texts`, the first one searched at `start` and one second apart, once each.
    private static func store(with texts: [String], start: Double = 0) async throws -> SmileySearchHistoryStore {
        let store = SmileySearchHistoryStore(persistence: InMemorySmallStorePersistence())
        for (index, text) in texts.enumerated() {
            try await store.record(text, resultCount: 1, at: date(start + Double(index)))
        }
        return store
    }

    @Test(
        "Only a trimmed search of 3 characters or more that found something is remembered",
        arguments: [
            ("abc", 1, true),
            ("ab", 5, false),
            ("  ab \n", 5, false),
            (" abc ", 1, true),
            ("abc", 0, false),
            ("abc", -1, false),
            ("été", 2, true),
            ("", 3, false)
        ]
    )
    func recordedOnlyWhenItQualifies(search: String, results: Int, remembered: Bool) async throws {
        let persistence = FailingSmallStorePersistence<SmileySearchHistoryDocument>()
        let store = SmileySearchHistoryStore(persistence: persistence)
        #expect(try await store.record(search, resultCount: results, at: Self.date(1)) == remembered)
        #expect(persistence.saveCount == (remembered ? 1 : 0))
        let texts = await store.recent(matching: "").map(\.text)
        #expect(texts == (remembered ? [search.trimmingCharacters(in: .whitespacesAndNewlines)] : []))
    }

    @Test func theSameSearchInAnotherCaseAddsToTheFirstEntry() async throws {
        let store = SmileySearchHistoryStore(persistence: InMemorySmallStorePersistence())
        try await store.record("Chat", resultCount: 3, at: Self.date(1))
        try await store.record("chat", resultCount: 3, at: Self.date(2))
        try await store.record(" CHAT", resultCount: 1, at: Self.date(3))
        try await store.record("chats", resultCount: 1, at: Self.date(4))
        let entries = await store.top(matching: "")
        #expect(entries == [
            SmileySearchHistoryEntry(text: "Chat", count: 3, lastSearchedAt: Self.date(3)),
            SmileySearchHistoryEntry(text: "chats", count: 1, lastSearchedAt: Self.date(4))
        ])
    }

    @Test func theFiftyMostRecentAreKept() async throws {
        let texts = (0..<SmileySearchHistoryStore.maximumEntries).map { "search\($0)" }
        let store = try await Self.store(with: texts)
        #expect(await store.recent(matching: "", limit: 100).count == 50)
        try await store.record("search50", resultCount: 1, at: Self.date(50))
        let kept = await store.recent(matching: "", limit: 100).map(\.text)
        #expect(kept.count == 50)
        #expect(!kept.contains("search0"))
        #expect(kept.first == "search50")
        #expect(kept.last == "search1")
    }

    @Test func aSearchAlreadyThereEvictsNothing() async throws {
        let texts = (0..<SmileySearchHistoryStore.maximumEntries).map { "search\($0)" }
        let store = try await Self.store(with: texts)
        try await store.record("SEARCH0", resultCount: 1, at: Self.date(60))
        let kept = await store.recent(matching: "", limit: 100)
        #expect(kept.count == 50)
        #expect(kept.first == SmileySearchHistoryEntry(text: "search0", count: 2, lastSearchedAt: Self.date(60)))
    }

    @Test func theSearchJustRecordedIsKeptWhenTheClockMovedBack() async throws {
        let texts = (0..<SmileySearchHistoryStore.maximumEntries).map { "search\($0)" }
        let store = try await Self.store(with: texts, start: 100)
        try await store.record("older", resultCount: 1, at: Self.date(1))
        let kept = await store.recent(matching: "", limit: 100).map(\.text)
        #expect(kept.count == 50)
        #expect(kept.contains("older"))
        #expect(!kept.contains("search0"))
        #expect(kept.contains("search1"))
    }

    @Test func recentIsNewestFirstAndLimited() async throws {
        let store = try await Self.store(with: ["chat", "chien", "cheval", "vache", "poule", "lapin", "canard"])
        #expect(await store.recent(matching: "").map(\.text) == ["canard", "lapin", "poule", "vache", "cheval"])
        #expect(await store.recent(matching: "", limit: 2).map(\.text) == ["canard", "lapin"])
        #expect(await store.recent(matching: "", limit: 0).isEmpty)
        #expect(await store.recent(matching: "", limit: -1).isEmpty)
        #expect(await store.recent(matching: "", limit: 7).count == 7)
        #expect(await store.recent(matching: "", limit: 8).count == 7)
    }

    @Test func topIsMostFrequentFirstThenMostRecentAndLimited() async throws {
        let texts = (0..<12).map { "search\($0)" }
        let store = try await Self.store(with: texts)
        try await store.record("search3", resultCount: 1, at: Self.date(20))
        try await store.record("search3", resultCount: 1, at: Self.date(21))
        try await store.record("search7", resultCount: 1, at: Self.date(22))
        let top = await store.top(matching: "").map(\.text)
        #expect(top == ["search3", "search7", "search11", "search10", "search9", "search8", "search6", "search5", "search4", "search2"])
        #expect(await store.top(matching: "", limit: 1).map(\.count) == [3])
        #expect(await store.top(matching: "", limit: 0).isEmpty)
        #expect(await store.top(matching: "", limit: 20).count == 12)
    }

    @Test func viewsSortWhateverTheStoredOrder() async throws {
        let stored = SmileySearchHistoryDocument(entries: [
            SmileySearchHistoryEntry(text: "oldest", count: 2, lastSearchedAt: Self.date(1)),
            SmileySearchHistoryEntry(text: "middle", count: 2, lastSearchedAt: Self.date(2)),
            SmileySearchHistoryEntry(text: "newest", count: 2, lastSearchedAt: Self.date(3)),
            SmileySearchHistoryEntry(text: "frequent", count: 5, lastSearchedAt: Self.date(0))
        ])
        let store = SmileySearchHistoryStore(persistence: InMemorySmallStorePersistence(stored))
        #expect(await store.top(matching: "").map(\.text) == ["frequent", "newest", "middle", "oldest"])
        #expect(await store.recent(matching: "").map(\.text) == ["newest", "middle", "oldest", "frequent"])
    }

    @Test func viewsKeepOnlySearchesContainingTheText() async throws {
        let store = try await Self.store(with: ["Chat", "chien", "vache"])
        #expect(await store.recent(matching: "CH").map(\.text) == ["vache", "chien", "Chat"])
        #expect(await store.top(matching: "ach").map(\.text) == ["vache"])
        #expect(await store.recent(matching: "zèbre").isEmpty)
        #expect(await store.recent(matching: "").count == 3)
    }
}
