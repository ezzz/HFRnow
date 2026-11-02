import HFRNetwork

/// Why a poll vote did not end with HFR's confirmation.
///
/// `notVotable`, `unsupportedPoll`, `invalidChoice`, `sessionNotConfirmed`, `missingToken` and `network` mean the vote
/// was not sent. `alreadyVoted`, `notLoggedIn` and `rejected` mean HFR refused it. `unconfirmed` means the vote may have
/// reached HFR: the app reloads the topic page to see the poll instead of voting again on its own.
/// No case carries a token or a cookie; `rejected` carries HFR's own sentence.
public enum PollVoteError: Error, Sendable, Equatable {
    /// The poll shows its results (closed, or already voted): there is no form to send; nothing was requested.
    case notVotable
    /// The voting form is not the captured one (other hidden fields, a non-numeric value, an answer field other than
    /// `reponse`, several choices): its body would be guessed, so nothing was requested.
    case unsupportedPoll
    /// The choice is not one of the poll's answers; nothing was requested.
    case invalidChoice
    /// The account session was not confirmed logged in just before the vote (LOT-044 `SessionRefreshFlow`, never
    /// `.valid` here); the vote was not sent.
    case sessionNotConfirmed(SessionHealth)
    /// The session holds no `hash_check`; nothing was sent.
    case missingToken
    /// HFR answered "Désolé, vous avez déjà voté !": this account, or a linked account of the same person, voted
    /// already (`W43`, `W44`).
    case alreadyVoted
    /// HFR refused the vote with its "vous devez être enregistré" sentence (the `W17c` shape; no vote answer captured).
    case notLoggedIn
    /// HFR refused the vote (a `.hop` with a link or a button, a bad token) with this sentence.
    case rejected(message: String?)
    /// The vote may have been counted, but HFR's confirmation of it was not read.
    case unconfirmed(PollVoteUncertainty)
    /// The vote could not be sent: it never reached HFR. Also the failure of the session check before it.
    case network(NetworkError)
}

/// Why a vote that may have reached HFR is not reported as done.
public enum PollVoteUncertainty: Sendable, Equatable {
    /// The exchange failed after the request was handed to the network (timeout, lost connection, HTTP error).
    case transport(NetworkError)
    /// HFR answered a page that is neither its vote confirmation nor a refusal (a redirect, another write's
    /// confirmation, another page); `message` is its `.hop` text, if any.
    case unrecognizedAnswer(message: String?)
}
