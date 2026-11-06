import HFRClient
import HFRModels
import HFRNetwork

/// Votes as the selected account; `LivePollVoter` in the app, a scripted double in tests.
protocol PollVoting: Sendable {
    /// Votes for the answer `choice` (a `PollOption.id`) of `poll`. Same contract as `PollVoteFlow.vote`: a result only
    /// when HFR confirmed this vote; `unconfirmed` when it may have been counted.
    func vote(_ choice: Int, in poll: Poll) async throws(PollVoteError) -> PollVoteResult
}

/// LOT-054's flow in the current account's session. The write path is the engine's: nothing is rebuilt here.
struct LivePollVoter: PollVoting {
    /// The current account's session (`AppEnvironment.session`).
    let session: HFRSession
    private let flow = PollVoteFlow()

    /// Creates a voter on `session`.
    init(session: HFRSession) {
        self.session = session
    }

    func vote(_ choice: Int, in poll: Poll) async throws(PollVoteError) -> PollVoteResult {
        try await flow.vote(choice, in: poll, session: session)
    }
}
