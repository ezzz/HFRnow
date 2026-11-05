import HFRClient
import HFRModels
import Observation

// Port of HFRswift/Swift/PollView.swift (PollViewModel: selection, submitVote) @ 2440d79. Differences: success only on HFR's own
// confirmation (LOT-054); an unconfirmed vote reloads the topic and cannot be sent again from the same sheet; no multi-choice
// (not captured, #111); GAP-059.
/// State of the poll sheet (LOT-136): the chosen answer and the outcome of the vote. The vote itself is `PollVoteFlow`'s.
@MainActor
@Observable
final class PollModel: Identifiable {
    /// Where the vote stands.
    enum Phase: Equatable {
        /// Nothing sent; the user may choose and vote.
        case idle
        /// The vote is on its way.
        case sending
        /// HFR confirmed the vote.
        case voted
        /// The vote may have reached HFR, or HFR said it was already given: the topic is reloaded, nothing is sent again.
        case settled
        /// The vote did not leave or was refused; another try is allowed.
        case failed
    }

    /// The poll on screen; replaced by the reloaded page's poll after a vote.
    private(set) var poll: Poll
    /// The chosen answer's `PollOption.id`.
    private(set) var selected: Int?
    /// Where the vote stands.
    private(set) var phase: Phase = .idle
    /// What to tell the user about the outcome; nil before any.
    private(set) var message: String?

    private let voter: (any PollVoting)?
    /// Reloads the topic page, which shows the poll's results; called after a vote that may have been counted.
    private let reload: @MainActor () async -> Void

    /// A model for `poll`; `voter` is nil when no account is current. `reload` refreshes the page the poll came from.
    init(poll: Poll, voter: (any PollVoting)?, reload: @escaping @MainActor () async -> Void) {
        self.poll = poll
        self.voter = voter
        self.reload = reload
    }

    /// The poll has a voting form this app can send (single choice, a current account).
    var offersVote: Bool {
        guard voter != nil, case .votable = poll.kind, poll.maxChoices == 1 else { return false }
        return phase != .voted && phase != .settled
    }

    /// A voting form is shown but no account is current: the answers are shown, not offered.
    var voterMissing: Bool {
        if case .votable = poll.kind { return voter == nil }
        return false
    }

    /// The "Voter" button is enabled.
    var canVote: Bool { offersVote && selected != nil && phase != .sending }

    /// The page was reloaded: the sheet shows the poll it now carries (the results after a vote); a page without a readable
    /// poll leaves the one shown.
    func pageDidReload(_ reloaded: Poll?) {
        if let reloaded { poll = reloaded }
    }

    /// A vote is on its way, was counted, or may have been: a sheet opened again must keep this model, never start from a
    /// fresh form over a vote that may have been counted.
    var holdsVote: Bool { phase == .sending || phase == .voted || phase == .settled }

    /// Chooses `id`; choosing the chosen answer again clears it (legacy). Ignored while sending, after a vote, or for an
    /// id that is not an answer of the poll.
    func toggle(_ id: Int) {
        guard offersVote, phase != .sending, case .votable(let options, _) = poll.kind, options.contains(where: { $0.id == id })
        else { return }
        selected = selected == id ? nil : id
    }

    /// Sends the chosen answer once. A confirmed vote and a vote that may have been counted both reload the topic; a vote
    /// that never left (or HFR refused) keeps the sheet open for another try.
    func vote() async {
        guard canVote, let voter, let choice = selected else { return }
        phase = .sending
        message = nil
        do throws(PollVoteError) {
            let result = try await voter.vote(choice, in: poll)
            phase = .voted
            message = PollMessages.confirmed(result)
            await reload()
        } catch {
            message = PollMessages.message(for: error)
            switch error {
            case .unconfirmed, .alreadyVoted:
                phase = .settled
                await reload()
            default:
                phase = .failed
            }
        }
    }
}
