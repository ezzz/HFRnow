import Foundation

/// The smiley searches that found something, on this device, for the recent and frequent suggestions (LOT-064).
///
/// Rules of legacy `SmileySearchHistoryStore` (`SmileySearchService.swift:78-140`, key `smileySearchHistory_v1`): a
/// search is remembered only with at least 3 characters (trimmed, as its caller `AnswerView.swift:1278-1279` did) and
/// at least one result; the same text in another case adds to the existing entry; the 50 most recent entries are kept.
public actor SmileySearchHistoryStore {
    /// The number of entries kept.
    public static let maximumEntries = 50
    /// The shortest search remembered, in characters.
    public static let minimumLength = 3

    private var state: SmallStoreState<SmileySearchHistoryDocument>

    /// Creates a store over `persistence`; nothing is read until the first call.
    public init(persistence: any SmallStorePersistence<SmileySearchHistoryDocument>) {
        state = SmallStoreState(persistence: persistence)
    }

    // MARK: Reading

    /// The most recent searches containing `text` (case-insensitive; every entry when empty), newest first.
    public func recent(matching text: String, limit: Int = 5) -> [SmileySearchHistoryEntry] {
        Array(entries(matching: text).sorted { $0.lastSearchedAt > $1.lastSearchedAt }.prefix(max(limit, 0)))
    }

    /// The most frequent searches containing `text` (case-insensitive; every entry when empty), the most recent first
    /// among equal counts.
    public func top(matching text: String, limit: Int = 10) -> [SmileySearchHistoryEntry] {
        let sorted = entries(matching: text).sorted { lhs, rhs in
            lhs.count == rhs.count ? lhs.lastSearchedAt > rhs.lastSearchedAt : lhs.count > rhs.count
        }
        return Array(sorted.prefix(max(limit, 0)))
    }

    /// The reason writes are refused, or nil when the store is usable (loading it if needed).
    public func loadFailure() -> SmallStoreError? {
        state.failure()
    }

    // MARK: Writing

    /// Remembers a search that returned `resultCount` smileys. Returns false, and saves nothing, when the trimmed
    /// search is shorter than `minimumLength` or found nothing.
    @discardableResult
    public func record(_ search: String, resultCount: Int, at date: Date = .now) throws(SmallStoreError) -> Bool {
        let text = search.trimmingCharacters(in: .whitespacesAndNewlines)
        guard text.count >= Self.minimumLength, resultCount > 0 else { return false }
        return try state.mutate { document in
            var recorded = SmileySearchHistoryEntry(text: text, count: 1, lastSearchedAt: date)
            if let index = document.entries.firstIndex(where: { $0.text.caseInsensitiveCompare(text) == .orderedSame }) {
                recorded = document.entries.remove(at: index)
                recorded.count += 1
                recorded.lastSearchedAt = date
            }
            // The entry just recorded is kept even if its date is the oldest (device clock moved back).
            let others = document.entries.sorted { $0.lastSearchedAt > $1.lastSearchedAt }.prefix(Self.maximumEntries - 1)
            document.entries = [recorded] + others
            return true
        }
    }

    // MARK: Recovery

    /// Reads the stored data again, for example after the user restored a file. Returns the failure if any.
    @discardableResult
    public func reload() -> SmallStoreError? {
        state.reload()
    }

    /// Sets the unreadable data aside (a `.corrupt` copy for files, never a deletion) and starts from an empty
    /// history. Only call it after the user agreed: this is the single way out of a failed load.
    public func discardUnreadableData() throws(SmallStoreError) {
        try state.discardUnreadableData()
    }

    // MARK: Internals

    private func entries(matching text: String) -> [SmileySearchHistoryEntry] {
        let entries = state.document()?.entries ?? []
        guard !text.isEmpty else { return entries }
        return entries.filter { $0.text.localizedCaseInsensitiveContains(text) }
    }
}
