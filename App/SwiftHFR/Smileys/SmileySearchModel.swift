import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRStorage
import Observation

// Port of HFRswift/Swift/AnswerView.swift (CombinedSmileyPickerView search: performSearch, suggestionChips, FavoriteSmileyDetailView
// keywords) @ 2440d79. Differences: a failed search says so instead of "Aucun smiley trouvé" (LESSONS 44); a text under 3
// characters explains itself; results are listed once per code (GAP-088).
/// State of the smiley search of the picker (LOT-105): the text, the results, the history chips and the wiki keywords.
///
/// Port of the search half of legacy's `CombinedSmileyPickerView` (`AnswerView.swift:1230-1345` @ 2440d79) over LOT-053's
/// `SmileyLookupFlow` and LOT-064's `SmileySearchHistoryStore`. Only the latest request counts: an older answer that
/// arrives after a newer search, a clear or a closed panel is dropped.
@MainActor
@Observable
final class SmileySearchModel {
    /// What the results area shows.
    enum Phase: Equatable {
        /// The catalogue (no search made, or the search was cleared).
        case library
        /// A request is in flight.
        case loading
        /// Smileys found, once per code, in the order served.
        case results([PickerSmiley])
        /// HFR found nothing (its own "no result" answer).
        case empty
        /// The text is under the minimum length; nothing was sent.
        case tooShort
        /// The search could not be made or read; the text tells why.
        case failed(String)
    }

    /// What the wiki keywords of the open detail show.
    enum Keywords: Equatable {
        /// Nothing asked yet.
        case idle
        /// The request is in flight.
        case loading
        /// The keywords of the wiki entry, in the order served (empty: the entry has none).
        case loaded([String])
        /// The entry could not be read; the text tells why.
        case failed(String)
    }

    /// The shortest search HFR is asked for, in characters (legacy `SmileySearchService.swift:19`).
    static let minimumLength = HFREndpoint.smileySearchMinimumLength
    /// The suggestions shown at most (legacy `suggestionChips`, `AnswerView.swift:1088-1093`).
    static let suggestionLimit = 5

    /// The search field; the view calls `refreshSuggestions()` when it changes.
    var text = ""
    private(set) var phase = Phase.library
    private(set) var keywords = Keywords.idle
    /// The history chips: the recent searches first, then the most frequent ones, matching `text`.
    private(set) var suggestions: [SmileySearchHistoryEntry] = []

    private let lookups: any SmileyLookups
    private let history: SmileySearchHistoryStore
    private var generation = 0
    private var keywordsGeneration = 0
    private var searchTask: Task<Void, Never>?

    /// A search model over the forum lookups and the device's history.
    init(lookups: any SmileyLookups, history: SmileySearchHistoryStore) {
        self.lookups = lookups
        self.history = history
    }

    /// The search can be sent: at least `minimumLength` characters once trimmed.
    var canSearch: Bool { trimmed.count >= Self.minimumLength }

    /// Why a typed text cannot be searched yet; nil when it can, or when the field is empty.
    var tooShortHint: String? {
        guard !trimmed.isEmpty, !canSearch else { return nil }
        return "Saisissez au moins \(Self.minimumLength) caractères pour lancer une recherche."
    }

    /// Whether the results area replaces the catalogue.
    var isSearching: Bool { phase != .library }

    private var trimmed: String { text.trimmingCharacters(in: .whitespacesAndNewlines) }

    // MARK: Search

    /// Starts a search for `query` (the field's text when nil), replacing the one in flight.
    func submit(_ query: String? = nil, requireAll: Bool) {
        searchTask?.cancel()
        searchTask = Task { await search(query, requireAll: requireAll) }
    }

    /// Searches `query` (the field's text when nil) and shows the outcome; a successful search is remembered.
    func search(_ query: String? = nil, requireAll: Bool) async {
        if let query, query != text { text = query }
        let query = trimmed
        generation += 1
        let mine = generation
        guard query.count >= Self.minimumLength else {
            phase = .tooShort
            return
        }
        phase = .loading
        let found: [ForumSmiley]
        do throws(SmileyLookupError) {
            found = try await lookups.search(query, requireAll: requireAll)
        } catch {
            guard mine == generation, !Task.isCancelled else { return }
            phase = .failed(Self.message(for: error))
            return
        }
        guard mine == generation, !Task.isCancelled else { return }
        let smileys = Self.listed(found)
        phase = smileys.isEmpty ? .empty : .results(smileys)
        // The history is a convenience: a store that refuses the write must not hide the results.
        _ = try? await history.record(query, resultCount: smileys.count)
        await refreshSuggestions()
    }

    /// Back to the catalogue; a search in flight is dropped.
    func clear() {
        searchTask?.cancel()
        generation += 1
        phase = .library
    }

    /// Drops everything in flight when the panel closes.
    func stop() {
        searchTask?.cancel()
        generation += 1
        keywordsGeneration += 1
    }

    // MARK: History

    /// Reads the chips for the current text: recent searches, then the frequent ones not already listed.
    func refreshSuggestions() async {
        let typed = text
        let recent = await history.recent(matching: typed, limit: Self.suggestionLimit)
        let chips: [SmileySearchHistoryEntry]
        if typed.isEmpty {
            chips = recent
        } else {
            let recentTexts = Set(recent.map(\.text))
            let top = await history.top(matching: typed, limit: 10).filter { !recentTexts.contains($0.text) }
            chips = Array((recent + top).prefix(Self.suggestionLimit))
        }
        // A newer keystroke has its own refresh.
        guard typed == text else { return }
        suggestions = chips
    }

    // MARK: Wiki keywords

    /// Reads the wiki keywords of `code` for the detail; an older request is dropped when another detail opens.
    func loadKeywords(for code: String) async {
        keywordsGeneration += 1
        let mine = keywordsGeneration
        keywords = .loading
        let detail: SmileyWikiDetail
        do throws(SmileyLookupError) {
            detail = try await lookups.wiki(code: code)
        } catch {
            guard mine == keywordsGeneration, !Task.isCancelled else { return }
            keywords = .failed(Self.message(for: error))
            return
        }
        guard mine == keywordsGeneration, !Task.isCancelled else { return }
        keywords = .loaded(detail.keywords)
    }

    /// Forgets the keywords of the detail that closed.
    func resetKeywords() {
        keywordsGeneration += 1
        keywords = .idle
    }

    // MARK: Helpers

    /// Each code once, first occurrence kept: HFR can serve one twice (`R53c`) and the grid identifies cells by code.
    static func listed(_ found: [ForumSmiley]) -> [PickerSmiley] {
        var seen = Set<String>()
        return found.compactMap { smiley in
            seen.insert(smiley.code).inserted ? PickerSmiley(code: smiley.code, imageURL: smiley.url) : nil
        }
    }

    private static func message(for error: SmileyLookupError) -> String {
        switch error {
        case .queryTooShort: "Saisissez au moins \(minimumLength) caractères pour lancer une recherche."
        case .invalidCode: "Code de smiley invalide."
        case .network: "Le forum ne répond pas. Vérifiez votre connexion et réessayez."
        case .page: "Le forum a répondu autrement que prévu. Réessayez plus tard."
        }
    }
}
