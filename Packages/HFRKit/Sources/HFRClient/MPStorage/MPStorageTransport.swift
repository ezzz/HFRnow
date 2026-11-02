import Foundation
import HFRModels
import HFRNetwork
import HFRParsing

/// Finds, reads, creates and writes the account's MPStorage document, the JSON first message of a private thread whose
/// subject is `MPStorageDocument.subject` (LOT-052, audit D8; legacy `Classes/MPStorage.m` @ 2440d79).
///
/// Every request runs in the session of the account whose storage it is (legacy used the main account's cookies,
/// `MPStorage.m:696-698, 772-774`). The document is always read from the first message's edit form, which holds it byte
/// for byte (`R60b`, HFR-PROTOCOL §7 X8): the rendered page only locates the thread and the message. A write is a
/// three-way merge against the copy re-read just before it (LOT-062), posted through LOT-048's edit, then read back.
/// Nothing is cached here: the app keeps `MPStorageLocation.post` per account and the last snapshot as the next `base`.
public struct MPStorageTransport: Sendable {
    /// Pages of the MP list searched before giving up: past it the thread may exist, so nothing is created.
    public static let maximumListPages = 50

    let posting = PostingFlow()

    /// Creates the transport.
    public init() {}

    /// The storage thread's id, searched page by page in the MP list (`MPStorage.m:692-736`); nil when the list ends
    /// without it.
    /// - Throws: `network`, `list`, `unexpectedPage`, `searchLimitReached`.
    public func findThread(in session: HFRSession) async throws(MPStorageTransportError) -> Int? {
        try await findThread(through: session)
    }

    /// Reads the document of thread `post`: its first page (`R60a`), then its first message's edit form (`R60b`).
    /// - Throws: `notAddressed` (stale `post`: find again), `threadPage`, `editLinkMissing`, `notStorageForm`,
    ///   `invalidDocument`, `posting` (form load), `unexpectedPage`, `network`.
    public func read(post: Int, in session: HFRSession) async throws(MPStorageTransportError) -> MPStorageSnapshot {
        try await read(post: post, through: session)
    }

    /// Writes `ours` (the last read copy `base` plus local edits) merged with the copy stored now, when the merge
    /// changes it, then reads it back. `base` nil merges without history (LOT-062: divergent items keep the forum's).
    /// - Throws: `document` (merge or write guards: nothing sent), `posting` (`.unconfirmed`: may be stored),
    ///   `notVerified` (confirmed, but the copy read back differs), and the errors of reading the edit form.
    public func save(
        _ ours: MPStorageDocument, base: MPStorageDocument?, at location: MPStorageLocation, stamp: MPStorageStamp,
        in session: HFRSession
    ) async throws(MPStorageTransportError) -> MPStorageSaveResult {
        try await save(ours, base: base, at: location, stamp: stamp, through: session)
    }

    /// Creates the storage thread with an empty document (legacy template, `MPStorage.m:738-767`), unless the MP list
    /// already has one, then reads it. Creating is a write the user agreed to (LOT-130 asks); a retry after an
    /// unconfirmed creation finds the thread instead of posting a second one.
    /// - Throws: the errors of `findThread`, `read` and posting, and `notFoundAfterCreation`.
    public func create(stamp: MPStorageStamp, in session: HFRSession) async throws(MPStorageTransportError) -> MPStorageCreation {
        try await create(stamp: stamp, through: session)
    }
}

// MARK: - Steps

extension MPStorageTransport {
    func findThread(through session: any PostingSession) async throws(MPStorageTransportError) -> Int? {
        let first = try Self.endpoint { () throws -> HTTPRequest in try HFREndpoint.privateMessages(page: 1) }
        func fetch(_ url: URL) async throws(MPStorageTransportError) -> MPStorageThreadSearch {
            let response = try await Self.get(.get(url), through: session)
            guard PostingFlow.isForumPage(response.url) else { throw .unexpectedPage }
            do throws(ListPageFailure) {
                return try MPStoragePageParser.findThread(in: response.decodedText().text, pageURL: response.url.absoluteString)
            } catch {
                throw .list(error)
            }
        }
        return try await Self.walk(from: first.url, maximumPages: Self.maximumListPages, fetch: fetch)
    }

    /// Walks the MP list from `first`, following each page's `nextPath`, until a page shows the thread or has no next
    /// page. A next link off the forum, or a page number that does not grow, stops the walk: HFR's pager always moves on.
    static func walk(
        from first: URL,
        maximumPages: Int,
        fetch: (URL) async throws(MPStorageTransportError) -> MPStorageThreadSearch
    ) async throws(MPStorageTransportError) -> Int? {
        var url = first
        var previous = 0
        for _ in 0..<maximumPages {
            switch try await fetch(url) {
            case .found(let post):
                return post
            case .notOnPage(let navigation):
                guard let path = navigation.nextPath else { return nil }
                guard
                    navigation.current > previous,
                    let next = HFREndpoint.absoluteURL(href: path), PostingFlow.isForumPage(next)
                else { throw .unexpectedPage }
                previous = navigation.current
                url = next
            }
        }
        throw .searchLimitReached(pages: maximumPages)
    }

    func read(post: Int, through session: any PostingSession) async throws(MPStorageTransportError) -> MPStorageSnapshot {
        let request = try Self.endpoint { () throws -> HTTPRequest in try HFREndpoint.privateThreadFirstPage(post: post) }
        let response = try await Self.get(request, through: session)
        // Not followed: a redirect answer is somewhere else than the thread asked for.
        guard !(300..<400).contains(response.statusCode) else { throw .unexpectedPage }
        let html = response.decodedText().text
        let page: MPStorageThreadPage
        do {
            page = try MPStoragePageParser.readDocument(in: html)
        } catch {
            throw .threadPage(error)
        }
        guard case .storage(let message) = page else { throw .notAddressed }
        // The same blocks as `readDocument`, in the same order: the first is the message it read.
        let actions = (try? MessageActionsParser.actions(in: html)) ?? []
        guard
            let editURL = actions.first?.editURL,
            Self.isEditLink(editURL, post: post, numreponse: message.numreponse)
        else { throw .editLinkMissing }
        let location = MPStorageLocation(post: post, numreponse: message.numreponse, editURL: editURL)
        return try await storedCopy(at: location, through: session).snapshot
    }

    func save(
        _ ours: MPStorageDocument, base: MPStorageDocument?, at location: MPStorageLocation, stamp: MPStorageStamp,
        through session: any PostingSession
    ) async throws(MPStorageTransportError) -> MPStorageSaveResult {
        let (form, theirs) = try await storedCopy(at: location, through: session)
        let merged: MPStorageMergeResult
        do {
            merged = try MPStorageMerge.merge(base: base, ours: ours, theirs: theirs.document, stamp: stamp)
        } catch {
            throw Self.documentError(error)
        }
        guard merged.needsWrite else { return MPStorageSaveResult(snapshot: theirs, conflicts: merged.conflicts, wrote: false) }
        let text = try Self.encode(merged.document)
        do {
            _ = try await posting.edit(text, with: form)
        } catch {
            throw .posting(error)
        }
        let stored: MPStorageSnapshot
        do {
            stored = try await storedCopy(at: location, through: session).snapshot
        } catch {
            throw .notVerified(stored: nil)
        }
        guard stored.text == text else { throw .notVerified(stored: stored) }
        return MPStorageSaveResult(snapshot: stored, conflicts: merged.conflicts, wrote: true)
    }

    func create(stamp: MPStorageStamp, through session: any PostingSession) async throws(MPStorageTransportError)
        -> MPStorageCreation {
        if let post = try await findThread(through: session) {
            return .existing(try await read(post: post, through: session))
        }
        let text = try Self.encode(Self.emptyDocument(stamp: stamp))
        let request = try Self.endpoint { () throws -> HTTPRequest in
            try HFREndpoint.newPrivateMessageForm(to: MPStorageDocument.recipient)
        }
        do {
            let form = try await posting.loadForm(at: request.url, through: session)
            _ = try await posting.newPrivateMessage(
                to: MPStorageDocument.recipient, subject: MPStorageDocument.subject, text: text, with: form
            )
        } catch {
            throw .posting(error)
        }
        // HFR's answer names no thread (`W10`): the new thread is found like any other.
        guard let post = try await findThread(through: session) else { throw .notFoundAfterCreation }
        return .created(try await read(post: post, through: session))
    }

    /// The edit form at `location` and the document it holds, after checking it is the storage message's form.
    func storedCopy(
        at location: MPStorageLocation, through session: any PostingSession
    ) async throws(MPStorageTransportError) -> (form: PostingForm, snapshot: MPStorageSnapshot) {
        let form: PostingForm
        do {
            form = try await posting.loadForm(at: location.editURL, through: session)
        } catch {
            throw .posting(error)
        }
        guard Self.isStorageForm(form, at: location), let text = form.form.textareaContent else { throw .notStorageForm }
        let document: MPStorageDocument
        do {
            document = try MPStorageCodec.decode(text)
        } catch {
            throw .invalidDocument
        }
        return (form, MPStorageSnapshot(location: location, text: text, document: document))
    }
}
