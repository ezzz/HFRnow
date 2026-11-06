import Foundation
import HFRClient
import HFRModels
import HFRParsing
import HFRStorage
@testable import SwiftHFR
import Testing

/// The smiley search's rules (LOT-105): the minimum length, results once per code, the history written only for a search
/// that found something, the chips, the keywords, and that only the latest request counts.
@MainActor
struct SmileySearchModelTests {
    private static let base = "https://forum-images.hardware.fr/icones/"

    private func smiley(_ code: String) -> ForumSmiley { ForumSmiley(code: code, url: url(Self.base + "x.gif")) }

    private func history() -> SmileySearchHistoryStore {
        SmileySearchHistoryStore(persistence: InMemorySmallStorePersistence())
    }

    private func model(
        _ lookups: ScriptedLookups, history: SmileySearchHistoryStore? = nil
    ) -> SmileySearchModel {
        SmileySearchModel(lookups: lookups, history: history ?? self.history())
    }

    // MARK: Minimum length

    @Test func aTextUnderTheMinimumLengthExplainsItselfAndSendsNothing() async {
        let lookups = ScriptedLookups()
        let search = model(lookups)
        search.text = " ab "
        #expect(!search.canSearch)
        #expect(search.tooShortHint?.contains("3 caractères") == true)
        await search.search(requireAll: false)
        #expect(search.phase == .tooShort)
        #expect(await lookups.searches.isEmpty)
    }

    @Test func theHintIsAbsentForAnEmptyFieldAndForALongEnoughText() {
        let search = model(ScriptedLookups())
        #expect(search.tooShortHint == nil)
        search.text = "abc"
        #expect(search.canSearch)
        #expect(search.tooShortHint == nil)
    }

    // MARK: Results and history

    @Test func resultsKeepTheServedOrderAndListEachCodeOnce() async {
        let lookups = ScriptedLookups(search: ["chat": .success([smiley("[:a]"), smiley("[:b]"), smiley("[:a]")])])
        let search = model(lookups)
        search.text = "  chat "
        await search.search(requireAll: true)
        #expect(search.phase == .results([
            PickerSmiley(code: "[:a]", imageURL: url(Self.base + "x.gif")),
            PickerSmiley(code: "[:b]", imageURL: url(Self.base + "x.gif"))
        ]))
        #expect(search.isSearching)
        let sent = await lookups.searches
        #expect(sent.map(\.text) == ["chat"])
        #expect(sent.map(\.requireAll) == [true])
    }

    @Test func aSearchThatFoundSomethingIsRemembered() async {
        let store = history()
        let search = model(ScriptedLookups(search: ["chat": .success([smiley("[:a]")])]), history: store)
        await search.search("chat", requireAll: false)
        #expect(await store.recent(matching: "", limit: 5).map(\.text) == ["chat"])
        #expect(search.suggestions.map(\.text) == ["chat"])
    }

    @Test func aSearchThatFoundNothingSaysSoAndIsNotRemembered() async {
        let store = history()
        let search = model(ScriptedLookups(search: ["zzzz": .success([])]), history: store)
        await search.search("zzzz", requireAll: false)
        #expect(search.phase == .empty)
        #expect(await store.recent(matching: "", limit: 5).isEmpty)
    }

    @Test func aFailedSearchIsNotTakenForNoResultAndIsNotRemembered() async {
        let store = history()
        let search = model(ScriptedLookups(search: ["chat": .failure(.network(.offline))]), history: store)
        await search.search("chat", requireAll: false)
        guard case .failed(let reason) = search.phase else {
            Issue.record("expected a failure, got \(search.phase)")
            return
        }
        #expect(reason.contains("connexion"))
        #expect(await store.recent(matching: "", limit: 5).isEmpty)
    }

    @Test func clearingGoesBackToTheCatalogue() async {
        let search = model(ScriptedLookups(search: ["chat": .success([smiley("[:a]")])]))
        await search.search("chat", requireAll: false)
        search.clear()
        #expect(search.phase == .library)
        #expect(!search.isSearching)
    }

    // MARK: Only the latest request counts

    @Test func anOlderAnswerArrivingLaterDoesNotReplaceTheNewerSearch() async {
        let lookups = ScriptedLookups(
            search: ["aaa": .success([smiley("[:old]")]), "bbb": .success([smiley("[:new]")])], gated: ["aaa"]
        )
        let search = model(lookups)
        let older = Task { await search.search("aaa", requireAll: false) }
        await lookups.waitUntilStarted("aaa")
        await search.search("bbb", requireAll: false)
        await lookups.release("aaa")
        await older.value
        #expect(search.phase == .results([PickerSmiley(code: "[:new]", imageURL: url(Self.base + "x.gif"))]))
        #expect(search.text == "bbb")
    }

    @Test func clearingDropsTheAnswerOfASearchInFlight() async {
        let lookups = ScriptedLookups(search: ["aaa": .success([smiley("[:old]")])], gated: ["aaa"])
        let search = model(lookups)
        let inFlight = Task { await search.search("aaa", requireAll: false) }
        await lookups.waitUntilStarted("aaa")
        #expect(search.phase == .loading)
        search.clear()
        await lookups.release("aaa")
        await inFlight.value
        #expect(search.phase == .library)
    }

    @Test func stoppingDropsTheAnswerOfASearchInFlight() async {
        let lookups = ScriptedLookups(search: ["aaa": .success([smiley("[:old]")])], gated: ["aaa"])
        let search = model(lookups)
        let inFlight = Task { await search.search("aaa", requireAll: false) }
        await lookups.waitUntilStarted("aaa")
        search.stop()
        #expect(search.phase == .library)
        await lookups.release("aaa")
        await inFlight.value
        #expect(search.phase == .library)
    }

    // MARK: Chips

    private func seeded() async -> SmileySearchHistoryStore {
        let store = history()
        let start = Date(timeIntervalSince1970: 1_000)
        for (index, text) in ["chat", "chaton", "chien", "chat noir", "souris", "chameau", "chats"].enumerated() {
            _ = try? await store.record(text, resultCount: 1, at: start + TimeInterval(index))
        }
        // "chien" is the most frequent; its date stays the one it had.
        _ = try? await store.record("chien", resultCount: 1, at: start + 2)
        _ = try? await store.record("chien", resultCount: 1, at: start + 2)
        return store
    }

    @Test func withAnEmptyFieldTheChipsAreTheFiveMostRecentSearches() async {
        let search = model(ScriptedLookups(), history: await seeded())
        await search.refreshSuggestions()
        #expect(search.suggestions.map(\.text) == ["chats", "chameau", "souris", "chat noir", "chien"])
    }

    @Test func aFrequentSearchOlderThanTheFiveRecentOnesCompletesTheChips() async {
        let store = history()
        let start = Date(timeIntervalSince1970: 1_000)
        for _ in 0..<3 { _ = try? await store.record("chaud", resultCount: 1, at: start) }
        for (index, text) in ["chat1", "chat2", "chat3"].enumerated() {
            _ = try? await store.record(text, resultCount: 1, at: start + TimeInterval(10 + index))
        }
        let search = model(ScriptedLookups(), history: store)
        search.text = "cha"
        await search.refreshSuggestions()
        // Three recent matches, then the frequent one not already listed.
        #expect(search.suggestions.map(\.text) == ["chat3", "chat2", "chat1", "chaud"])
    }

    @Test func withATextTheChipsAreRecentMatchesThenFrequentOnesNotAlreadyListed() async {
        let search = model(ScriptedLookups(), history: await seeded())
        search.text = "CHA"
        await search.refreshSuggestions()
        #expect(search.suggestions.map(\.text) == ["chats", "chameau", "chat noir", "chaton", "chat"])
        search.text = "chi"
        await search.refreshSuggestions()
        #expect(search.suggestions.map(\.text) == ["chien"])
    }

    // MARK: Keywords

    @Test func keywordsAreLoadedInTheOrderServed() async {
        let detail = SmileyWikiDetail(code: "[:a]", imageURL: nil, keywords: ["chat", "noir", "miaou"])
        let lookups = ScriptedLookups(wiki: ["[:a]": .success(detail)])
        let search = model(lookups)
        #expect(search.keywords == .idle)
        await search.loadKeywords(for: "[:a]")
        #expect(search.keywords == .loaded(["chat", "noir", "miaou"]))
        search.resetKeywords()
        #expect(search.keywords == .idle)
    }

    @Test func unreadableKeywordsSayWhy() async {
        let search = model(ScriptedLookups(wiki: ["[:a]": .failure(.network(.offline))]))
        await search.loadKeywords(for: "[:a]")
        guard case .failed(let reason) = search.keywords else {
            Issue.record("expected a failure, got \(search.keywords)")
            return
        }
        #expect(!reason.isEmpty)
    }

    @Test func keywordsOfAClosedDetailDoNotLandOnTheNextOne() async {
        let first = SmileyWikiDetail(code: "[:a]", imageURL: nil, keywords: ["un"])
        let second = SmileyWikiDetail(code: "[:b]", imageURL: nil, keywords: ["deux"])
        let lookups = ScriptedLookups(wiki: ["[:a]": .success(first), "[:b]": .success(second)], gated: ["[:a]"])
        let search = model(lookups)
        let older = Task { await search.loadKeywords(for: "[:a]") }
        await lookups.waitUntilStarted("[:a]")
        await search.loadKeywords(for: "[:b]")
        await lookups.release("[:a]")
        await older.value
        #expect(search.keywords == .loaded(["deux"]))
    }

    // MARK: Picker

    @Test func tappingAKeywordClosesTheDetailAndSearchesIt() async {
        let lookups = ScriptedLookups(search: ["miaou": .success([smiley("[:a]")])])
        let search = model(lookups)
        let picker = SmileyPickerModel(
            catalogue: [], store: AppSmileyFavoritesStore(persistence: InMemorySmallStorePersistence()), account: "user1",
            search: search
        )
        picker.tap(result: PickerSmiley(code: "[:a]", imageURL: url(Self.base + "x.gif")))
        #expect(picker.presented?.code == "[:a]")
        picker.searchKeyword("miaou", requireAll: false)
        #expect(picker.presented == nil)
        #expect(search.text == "miaou")
        await lookups.waitUntilSearched("miaou")
        #expect(await lookups.searches.map(\.text) == ["miaou"])
    }
}

/// Lookups answered from a script; a gated text waits for `release`, so tests order answers without any clock.
private actor ScriptedLookups: SmileyLookups {
    struct Sent: Equatable {
        let text: String
        let requireAll: Bool
    }

    private let searchAnswers: [String: Result<[ForumSmiley], SmileyLookupError>]
    private let wikiAnswers: [String: Result<SmileyWikiDetail, SmileyLookupError>]
    private let gated: Set<String>
    private(set) var searches: [Sent] = []
    private var started: Set<String> = []
    private var startWaiters: [String: [CheckedContinuation<Void, Never>]] = [:]
    private var gates: [String: CheckedContinuation<Void, Never>] = [:]
    private var released: Set<String> = []

    init(
        search: [String: Result<[ForumSmiley], SmileyLookupError>] = [:],
        wiki: [String: Result<SmileyWikiDetail, SmileyLookupError>] = [:],
        gated: Set<String> = []
    ) {
        searchAnswers = search
        wikiAnswers = wiki
        self.gated = gated
    }

    func search(_ text: String, requireAll: Bool) async throws(SmileyLookupError) -> [ForumSmiley] {
        searches.append(Sent(text: text, requireAll: requireAll))
        await enter(text)
        return try (searchAnswers[text] ?? .success([])).get()
    }

    func wiki(code: String) async throws(SmileyLookupError) -> SmileyWikiDetail {
        await enter(code)
        return try (wikiAnswers[code] ?? .failure(.invalidCode)).get()
    }

    /// Returns once the request for `key` has reached the lookup.
    func waitUntilStarted(_ key: String) async {
        if started.contains(key) { return }
        await withCheckedContinuation { startWaiters[key, default: []].append($0) }
    }

    /// Same as `waitUntilStarted`, for a search that was spawned by the model.
    func waitUntilSearched(_ key: String) async { await waitUntilStarted(key) }

    /// Lets the gated request for `key` answer.
    func release(_ key: String) {
        released.insert(key)
        gates.removeValue(forKey: key)?.resume()
    }

    private func enter(_ key: String) async {
        started.insert(key)
        for waiter in startWaiters.removeValue(forKey: key) ?? [] { waiter.resume() }
        guard gated.contains(key), !released.contains(key) else { return }
        await withCheckedContinuation { gates[key] = $0 }
    }
}
