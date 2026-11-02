import Foundation
import HFRModels
import HFRNetwork
import HFRParsing

/// Why an MPStorage operation failed (LOT-052).
///
/// Every case but `posting(.unconfirmed)` and `notVerified` means nothing was written. No case carries the document
/// text: it holds member pseudos.
public enum MPStorageTransportError: Error, Sendable, Equatable {
    /// A read request failed before any answer was read (offline, timeout, cancelled, HTTP refused by the session).
    case network(NetworkError)
    /// A page of the MP list could not be read (logged out, maintenance, another page).
    case list(ListPageFailure)
    /// No storage thread on the first `pages` pages of the MP list: whether one exists further is unknown, so the
    /// caller must not create one.
    case searchLimitReached(pages: Int)
    /// A page answered from another place than the one asked (a redirect, a pager link off the forum, a pager that
    /// does not move forward): nothing read from it is trusted.
    case unexpectedPage
    /// The thread page is not the storage thread's first page (LOT-038).
    case threadPage(MPStoragePageError)
    /// HFR says the thread is not for this account ("Ce message ne vous est pas destiné", `RA5`): the cached `post` is
    /// stale (deleted thread, another account's id). Find the thread again.
    case notAddressed
    /// The first message has no edit link of its own thread and message: it cannot be written.
    case editLinkMissing
    /// The edit form is not the storage message's (another thread, message or subject, not an edit form).
    case notStorageForm
    /// The stored text is not a readable document (invalid JSON, no `data`, a lone surrogate escape).
    case invalidDocument
    /// The merged document cannot be written (no `0.1` entry, a non-BMP character, too large): nothing was sent.
    case document(MPStorageError)
    /// Loading a form or posting it failed; `.unconfirmed` means the write may have been stored.
    case posting(PostingError)
    /// HFR confirmed the new thread but the MP list does not show it.
    case notFoundAfterCreation
    /// HFR confirmed the write but the stored copy read back is not the text sent (a concurrent write, or HFR changed
    /// it); `stored` is that copy when it could be read. Read again and merge before writing again.
    case notVerified(stored: MPStorageSnapshot?)
}
