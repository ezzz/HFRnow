import HFRNetwork

/// Why a flag write or a read mark did not end with HFR's confirmation.
///
/// Every case but `unconfirmed` means nothing reached HFR, so the user may try again. `unconfirmed` means the request may
/// have reached HFR: the app reloads the list or the topic to see the state instead of resending on its own.
/// No case carries a token or a cookie; `rejected` carries HFR's own sentence.
public enum TopicFlagError: Error, Sendable, Equatable {
    /// The link is not an `https` `forum.hardware.fr` link of this write (path, `config=hfr.inc`, one forum `cat`, one
    /// positive `post`); nothing was requested.
    case invalidLink
    /// The topic is not a forum topic with a positive number, or the page is below 1; nothing was requested.
    case invalidTopic
    /// The session holds no `hash_check` for the list removal; nothing was sent. Record the favourites page's token first.
    case missingToken
    /// HFR refused the write with its "vous devez être enregistré" sentence (`W17c`).
    case notLoggedIn
    /// HFR refused the write (a `.hop` with a link or a button, a bad token) with this sentence.
    case rejected(message: String?)
    /// The write may have been done, but HFR's confirmation of it was not read.
    case unconfirmed(TopicFlagUncertainty)
    /// The request could not be sent: nothing reached HFR.
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
    /// HFR answered "avec succès" to a write whose confirmation was never captured (`removeFavoriteFromList`).
    case confirmationNotCaptured(message: String)
}
