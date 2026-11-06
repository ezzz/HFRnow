import HFRNetwork

/// Why an alert was not prepared or not sent.
///
/// Every case but `unconfirmed` means nothing was sent, so the user may try again. `unconfirmed` means the alert may
/// have reached HFR: the app must not resend it on its own. No case carries the reason, a token or a cookie;
/// `formUnavailable` carries HFR's own sentence.
public enum ModeratorAlertError: Error, Sendable, Equatable {
    /// The alert link, the page it redirected to or the form's action is not the alert page of the same forum message
    /// on `https` `forum.hardware.fr`; nothing was sent.
    case invalidLink
    /// The page is neither the form nor "already alerted"; `message` is its `.hop` text, if any.
    case formUnavailable(message: String?)
    /// The session is not logged in: the form came with an empty `hash_check`, or HFR answered with its "vous devez être
    /// enregistré" sentence (`W17c`) or its alert one, "Vous devez être identifié pour prévenir les modérateurs" (`R89`,
    /// `W47`).
    case notLoggedIn
    /// The session logged out, or logged in as another account, since the alert page was read: the form's `hash_check`
    /// is no longer the session's. Nothing was sent; prepare the alert again.
    case sessionChanged
    /// The form holds something that cannot be sent like a browser; `reason` names it.
    case unsupportedForm(reason: String)
    /// The reason is empty after trimming whitespace and newlines (legacy Swift refused it too, `ReplyService.swift:1468-1471`).
    case emptyReason
    /// The reason holds characters outside the Basic Multilingual Plane (most emoji), refused before sending as for
    /// posts (decision Q-3); distinct characters in order. Legacy removed them silently (`AlerteModoViewController.m:209`).
    case unsupportedCharacters([Character])
    /// HFR refused the alert: a `.hop` with a back link that is not its confirmation (flood `W20a`, empty body `W17a`),
    /// or its plain-text token refusal (`W17b`). `message` is HFR's own sentence.
    case rejected(message: String?)
    /// The alert may have been sent, but HFR's answer was not read. Never retried automatically.
    case unconfirmed(PostingUncertainty)
    /// The page could not be fetched, or the request could not be sent: nothing was sent.
    case network(NetworkError)
}
