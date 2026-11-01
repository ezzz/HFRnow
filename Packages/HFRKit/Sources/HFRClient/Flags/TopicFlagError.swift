import HFRNetwork

/// Why a flag write or a read mark did not end with HFR's confirmation.
///
/// `invalidLink`, `invalidTopic`, `sessionNotConfirmed`, `missingToken` and `network` mean the write was not sent.
/// `notLoggedIn` and `rejected` mean HFR answered with a refusal by LOT-037's shape rule (no `addflag` or `delflag`
/// refusal is captured), so the user may try again. `unconfirmed` means the request may have reached HFR: the app reloads
/// the list or the topic to see the state instead of resending on its own.
/// No case carries a token or a cookie; `rejected` carries HFR's own sentence.
public enum TopicFlagError: Error, Sendable, Equatable {
    /// The link is not an `https` `forum.hardware.fr` link of this write (path, `config=hfr.inc`, one forum `cat`, one
    /// positive `post`); nothing was requested.
    case invalidLink
    /// The topic is not a forum topic with a positive number, or the page is below 1; nothing was requested.
    case invalidTopic
    /// The account session was not confirmed logged in just before the write (LOT-044 `SessionRefreshFlow`, never
    /// `.valid` here); the write was not sent. HFR answers a write without a session with the success page (`P03q`), so
    /// the app asks for a new login or checks the session again instead of retrying.
    case sessionNotConfirmed(SessionHealth)
    /// The session holds no `hash_check` for the list removal; nothing was sent. Record the favourites page's token first.
    case missingToken
    /// HFR refused the write with its "vous devez être enregistré" sentence (`W17c`).
    case notLoggedIn
    /// HFR refused the write (a `.hop` with a link or a button, a bad token) with this sentence.
    case rejected(message: String?)
    /// The write may have been done, but HFR's confirmation of it was not read.
    case unconfirmed(TopicFlagUncertainty)
    /// The write could not be sent: it never reached HFR. Also the failure of the session check before it (its GET of the
    /// profile page may have reached HFR, the write did not).
    case network(NetworkError)
}

/// Why a write that may have reached HFR is not reported as done.
public enum TopicFlagUncertainty: Sendable, Equatable {
    /// The exchange failed after the request was handed to the network (timeout, lost connection, HTTP error).
    case transport(NetworkError)
    /// HFR answered a page that is neither a confirmation nor a refusal (a redirect, another page); `message` is its
    /// `.hop` text, if any.
    case unrecognizedAnswer(message: String?)
    /// HFR confirmed something, but not with this write's sentence (for example "Drapeau effacé" after an `addflag`).
    case unexpectedConfirmation(message: String)
}
