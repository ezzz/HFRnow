import Foundation
import HFRModels
import HFRNetwork

/// HFR's confirmation that an MP thread left the account's MP list.
///
/// The other participants still list the thread (`R95k`); for this account its URL now answers "Ce message ne vous est
/// pas destiné, désolé" (`R96c`).
public struct MPThreadDeletion: Sendable, Equatable {
    /// The thread deleted.
    public var thread: TopicID
    /// HFR's sentence, "Action effectuée avec succès".
    public var message: String
    /// The MP list page HFR refreshes to (`/forum1.php?config=hfr.inc&cat=prive&page=1…`), always `https` on the forum.
    public var refreshURL: URL

    /// Creates a deletion result.
    public init(thread: TopicID, message: String, refreshURL: URL) {
        self.thread = thread
        self.message = message
        self.refreshURL = refreshURL
    }
}

/// Why an MP thread delete did not end with HFR's confirmation.
///
/// `invalidThread`, `sessionNotConfirmed`, `sessionChanged`, `missingToken` and `network` mean the delete was not sent.
/// `notLoggedIn` and `rejected` mean HFR refused it (a bad token gives `W64x`'s plain text), so the user may try again.
/// `unconfirmed` means the request may have reached HFR: the app reloads the MP list instead of resending on its own.
/// No case carries a token or a cookie; `rejected` carries HFR's own sentence.
public enum MPThreadDeleteError: Error, Sendable, Equatable {
    /// The thread is not a private-messages topic with a positive number; nothing was requested.
    case invalidThread
    /// The account session was not confirmed logged in just before the delete (LOT-044, never `.valid` here); nothing
    /// was sent.
    case sessionNotConfirmed(SessionHealth)
    /// A login (another account, or the same one again) or a logout landed in the session during the check: the check
    /// no longer vouches for the session, so nothing was sent.
    case sessionChanged
    /// The session holds no `hash_check` after the check; nothing was sent.
    case missingToken
    /// HFR refused the delete with its "vous devez être enregistré" sentence (`W17c`'s shape).
    case notLoggedIn
    /// HFR refused the delete (its bad-token plain text `W64x`, a `.hop` with a link or a button) with this sentence.
    case rejected(message: String?)
    /// The delete may have been done, but HFR's confirmation of it was not read.
    case unconfirmed(MPThreadDeleteUncertainty)
    /// The delete could not be sent: it never reached HFR. Also the failure of the session check before it (its GET of
    /// the profile page may have reached HFR, the delete did not).
    case network(NetworkError)
}

/// Why a delete that may have reached HFR is not reported as done.
public enum MPThreadDeleteUncertainty: Sendable, Equatable {
    /// The exchange failed after the request was handed to the network (timeout, lost connection, HTTP error).
    case transport(NetworkError)
    /// HFR answered a page that is neither a confirmation nor a refusal (a redirect, another page); `message` is its
    /// `.hop` text, if any.
    case unrecognizedAnswer(message: String?)
    /// HFR confirmed something, but not this delete (another sentence, or a refresh to another page than the MP list).
    case unexpectedConfirmation(message: String)
}
