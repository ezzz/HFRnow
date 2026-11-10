import Foundation
@testable import HFRStorage
import Testing

@Suite("Smiley search history merge (LOT-067)")
struct SmileySearchHistoryMergeTests {
    private func entry(_ text: String, _ count: Int, _ time: TimeInterval) -> SmileySearchHistoryEntry {
        SmileySearchHistoryEntry(text: text, count: count, lastSearchedAt: Date(timeIntervalSinceReferenceDate: time))
    }

    @Test("merge keeps counts and dates, the stored entry wins on the same text in any case, blanks skipped")
    func merge() async throws {
        let persistence = InMemorySmallStorePersistence<SmileySearchHistoryDocument>()
        let store = SmileySearchHistoryStore(persistence: persistence)
        try await store.record("chat", resultCount: 2, at: Date(timeIntervalSinceReferenceDate: 10))
        let added = try await store.merge([entry("CHAT", 9, 50), entry("rire", 4, 20), entry("  ", 1, 30)])
        #expect(added == 1)
        #expect(await store.top(matching: "") == [entry("rire", 4, 20), entry("chat", 1, 10)])
        #expect(try await store.merge([entry("Chat", 2, 5)]) == 0)
    }

    @Test("merge keeps the 50 most recent")
    func mergeCap() async throws {
        let store = SmileySearchHistoryStore(persistence: InMemorySmallStorePersistence<SmileySearchHistoryDocument>())
        let entries = (0..<60).map { entry("term\($0)", 1, TimeInterval($0)) }
        #expect(try await store.merge(entries) == 50)
        let kept = await store.recent(matching: "", limit: 100)
        #expect(kept.count == 50)
        #expect(kept.last?.text == "term10")
    }
}
