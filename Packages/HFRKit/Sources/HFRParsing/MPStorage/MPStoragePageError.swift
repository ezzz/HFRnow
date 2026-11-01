/// Why the storage thread page gave no document. Never an empty document in its place: legacy turned the feature off
/// on these (`MPStorage.m:888-891`), the caller decides. Payloads never carry page content (the JSON holds pseudos).
public enum MPStoragePageError: Error, Sendable, Equatable {
    /// The page or its message blocks could not be read.
    case unreadablePage(ParsingError)
    /// No message on the page and not the "not addressed" notice: a login wall, maintenance or another page.
    case noMessage
    /// The page is a thread whose subject is not `MPStorageDocument.subject`.
    case notStorageThread
    /// The page starts with the copy of a previous page's last message: it is not the thread's first page.
    case notFirstPage
    /// The first message has no paragraph to read the JSON from.
    case missingParagraph
    /// The text is not an MPStorage document (invalid JSON, no `data`, a lone surrogate escape).
    case invalidDocument
}
