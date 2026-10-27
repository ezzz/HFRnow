import HFRNetwork

/// Why a write did not end with HFR's confirmation.
///
/// Every case but `unconfirmed` means nothing was posted, so the user may try again. `unconfirmed` means the request may
/// have reached HFR: the app must not resend it on its own (double post), only tell the user to check the topic.
/// No case carries the user's text, a token or a cookie; `rejected` and `formUnavailable` carry HFR's own sentence.
public enum PostingError: Error, Sendable, Equatable {
    /// The form URL is not an `https` page of `forum.hardware.fr`; nothing was requested.
    case invalidFormURL
    /// The page has no `hop` form (locked topic, message not addressed to the account…); `message` is its `.hop` text.
    case formUnavailable(message: String?)
    /// The session is not logged in: the form came with an empty `hash_check` or `pseudo` (`R40b`), or HFR refused the
    /// write with its "vous devez être enregistré" sentence (`W17c`).
    case notLoggedIn
    /// The form has no `action` on the forum origin; no default is substituted (HFR-PROTOCOL §3.1 step 4).
    case missingAction
    /// The form holds something this engine does not know how to send like a browser; `reason` names it.
    case unsupportedForm(reason: String)
    /// The form is not the one this write needs (a new-topic form passed to `reply`, for example).
    case formMismatch(expected: PostingForm.Shape, actual: PostingForm.Shape)
    /// A required input is empty after trimming whitespace and newlines.
    case emptyInput(PostingInput)
    /// An input holds characters outside the Basic Multilingual Plane (most emoji): HFR cuts the text at the first one
    /// and still answers success (`W12`), so they are refused before sending (decision Q-3). Distinct characters in order.
    case unsupportedCharacters(PostingInput, [Character])
    /// The sub-category is not one of the form's options.
    case unknownSubcategory
    /// A subject was given for a message whose subject cannot be edited (a reply, a later post of a thread).
    case subjectNotEditable
    /// An option was set that the form does not offer; the payload is the form field name.
    case optionNotOffered(String)
    /// The edit form has no `delete` box (HFR serves it without one for another account's message, `R44`).
    case deleteNotOffered
    /// Deleting this message deletes the whole thread; the caller must confirm it explicitly.
    case wholeTopicDeletionNotConfirmed
    /// HFR refused the write (flood, empty text, bad token…) with this sentence: nothing was posted.
    case rejected(message: String?)
    /// The write may have been posted, but HFR's confirmation was not read. Never retried automatically.
    case unconfirmed(PostingUncertainty)
    /// The form could not be fetched, or the request could not be sent: nothing was posted.
    case network(NetworkError)
}

/// What the user typed, as named in `PostingError`.
public enum PostingInput: String, Sendable, Hashable {
    /// The message text (`content_form`).
    case text
    /// The topic or thread subject (`sujet`).
    case subject
    /// The recipient of a new private message (`dest`).
    case recipient
}

/// Why a write that may have reached HFR is not reported as done.
public enum PostingUncertainty: Sendable, Equatable {
    /// The exchange failed after the request was handed to the network (timeout, lost connection, cancellation, HTTP
    /// error): HFR may have stored the message.
    case transport(NetworkError)
    /// HFR answered a page that is neither its confirmation nor a refusal; `message` is its `.hop` text, if any.
    case unrecognizedAnswer(message: String?)
    /// HFR answered a confirmation, but not the sentence of this write (spec "Per-flow confirmation").
    case unexpectedConfirmation(message: String?)
}
