import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import Observation

// Port of HFRswift/Swift/TopicSearchSheetView.swift (TopicSearchSheetView) and HFRswift/Swift/TopicSearchService.swift
// (TopicSearchParams, ObjCTopicSearchService) @ 2440d79. Differences: the search goes through HFRClient (LOT-046); a
// refusal or an unreadable answer is told apart from "no result"; no "Filtrer" nor "Depuis le début" toggle (GAP-135: the
// answer of a POST with `filter=1` is not captured; GAP-136: a continued search is not captured); a match opens at its message.
/// State of the in-topic search sheet (LOT-113): the two criteria, one search at a time, and the target of the match.
@MainActor
@Observable
final class TopicSearchModel: Identifiable {
    /// What the sheet shows below the criteria.
    enum State: Equatable {
        case idle
        case searching
        /// Nothing to open: HFR's "no result", a refusal or a failure, in French, shown in the sheet.
        case failed(String)
    }

    /// The word to find.
    var word = ""
    /// The author (`spseudo`) to find.
    var author = ""
    /// Search progress.
    private(set) var state = State.idle

    private let topic: TopicID
    private let searcher: any TopicSearching
    private var generation = 0
    private var task: Task<ReaderTarget?, Never>?

    /// A sheet that searches `topic`.
    init(topic: TopicID, searcher: any TopicSearching) {
        self.topic = topic
        self.searcher = searcher
    }

    /// At least one criterion is filled (legacy `isSubmittable`) and no search is running.
    var canSubmit: Bool {
        state != .searching && !(word.trimmed.isEmpty && author.trimmed.isEmpty)
    }

    /// Runs the search; the target of the match, or nil with `state` telling why (also nil when cancelled or superseded).
    func submit() async -> ReaderTarget? {
        guard canSubmit else { return nil }
        generation += 1
        let mine = generation
        state = .searching
        let query = TopicSearchQuery(topic: topic, word: word.trimmed, author: author.trimmed, filterEnabled: false)
        let (searcher, topic) = (self.searcher, self.topic)
        let task = Task { () -> ReaderTarget? in
            let outcome: Outcome
            do throws(TopicSearchError) {
                outcome = Self.outcome(of: try await searcher.search(query), topic: topic)
            } catch {
                outcome = Self.outcome(of: error)
            }
            return self.finish(outcome, generation: mine)
        }
        self.task = task
        return await task.value
    }

    /// Stops the running search (the sheet closes); nothing is shown for it afterwards.
    func cancel() {
        task?.cancel()
        task = nil
        generation += 1
        if state == .searching { state = .idle }
    }

    private enum Outcome {
        case found(ReaderTarget)
        case failed(String)
        case cancelled
    }

    private func finish(_ outcome: Outcome, generation mine: Int) -> ReaderTarget? {
        guard mine == generation else { return nil }
        task = nil
        switch outcome {
        case .found(let target):
            state = .idle
            return target
        case .failed(let message):
            state = .failed(message)
        case .cancelled:
            state = .idle
        }
        return nil
    }

    private static func outcome(of result: TopicSearchResult, topic: TopicID) -> Outcome {
        switch result {
        case .match(let url):
            if let target = ReaderTarget(searchMatch: url, topic: topic) { return .found(target) }
            return .failed("Réponse inattendue du forum.")
        case .noMatch:
            // Legacy `TopicSearchError.noResultURL`: a message in the sheet, never an empty screen.
            return .failed("Aucun résultat n'a été trouvé.")
        }
    }

    private static func outcome(of error: TopicSearchError) -> Outcome {
        switch error {
        case .network(.cancelled): .cancelled
        case .network: .failed("Impossible de joindre le forum.")
        case .missingToken, .notLoggedIn: .failed("Connecte-toi pour rechercher dans ce sujet.")
        case .rejected(let message): .failed(message ?? "Le forum a refusé la recherche.")
        case .invalidLocation, .unrecognizedAnswer: .failed("Réponse inattendue du forum.")
        }
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
