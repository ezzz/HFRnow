/// The per-account blocklist and the global allowlist.
///
/// Legacy `BlackList.m` could overwrite the stored lists with an empty dictionary: `-init` skipped `load` when no
/// account was current, and the next `save` wrote the empty in-memory state (audit E §7.2). Here the first access
/// loads the document and, if that fails (corrupt, unreadable, newer format), every read answers "empty" but every
/// write throws and nothing is saved, until `reload()` succeeds or `discardUnreadableData()` is called explicitly.
///
/// Server synchronisation (MPStorage) is not here; `replaceBlocklist` lets the app store a list it fetched.
public actor PseudoListStore {
    private enum State {
        case unloaded
        case loaded(PseudoListDocument)
        case failed(PseudoListError)
    }

    private let persistence: any PseudoListPersistence
    private var state = State.unloaded

    /// Creates a store over `persistence`; nothing is read until the first call.
    public init(persistence: any PseudoListPersistence) {
        self.persistence = persistence
    }

    // MARK: Reading

    /// The blocklist of an account, in the order entries were added. Empty while the stored data is unreadable.
    public func blocklist(for account: String) -> [PseudoListEntry] {
        document?.blocklists[PseudoNormalizer.normalize(account)] ?? []
    }

    /// The global allowlist, in the order entries were added.
    public func allowlist() -> [PseudoListEntry] {
        document?.allowlist ?? []
    }

    /// Whether `pseudo` is on the account's blocklist.
    public func isBlocked(_ pseudo: String, account: String) -> Bool {
        Self.index(of: pseudo, in: blocklist(for: account)) != nil
    }

    /// Whether `pseudo` is allowed. A blocked pseudo is never allowed, as in legacy `isWL:` (`BlackList.m:119-121`).
    public func isAllowed(_ pseudo: String, account: String) -> Bool {
        !isBlocked(pseudo, account: account) && Self.index(of: pseudo, in: allowlist()) != nil
    }

    /// The reason writes are refused, or nil when the store is usable (loading it if needed).
    public func loadFailure() -> PseudoListError? {
        if case .failed(let error) = loadedState() { return error }
        return nil
    }

    // MARK: Writing

    /// Adds a pseudo to the account's blocklist. Returns false when it was already there (the list is then untouched).
    @discardableResult
    public func block(_ pseudo: String, account: String) throws -> Bool {
        try mutate { document in
            try Self.insert(pseudo, into: &document.blocklists[PseudoNormalizer.normalize(account), default: []])
        }
    }

    /// Removes a pseudo from the account's blocklist. Returns false when it was not there.
    @discardableResult
    public func unblock(_ pseudo: String, account: String) throws -> Bool {
        try mutate { document in
            let key = PseudoNormalizer.normalize(account)
            guard var list = document.blocklists[key] else { return false }
            let removed = Self.remove(pseudo, from: &list)
            document.blocklists[key] = list.isEmpty ? nil : list
            return removed
        }
    }

    /// Replaces the account's blocklist, for example with the list fetched from MPStorage. Duplicates collapse
    /// and empty pseudos are dropped. Returns false when the resulting list equals the current one.
    @discardableResult
    public func replaceBlocklist(with pseudos: [String], account: String) throws -> Bool {
        try mutate { document in
            var list: [PseudoListEntry] = []
            for pseudo in pseudos { _ = try? Self.insert(pseudo, into: &list) }
            let key = PseudoNormalizer.normalize(account)
            guard list != (document.blocklists[key] ?? []) else { return false }
            document.blocklists[key] = list.isEmpty ? nil : list
            return true
        }
    }

    /// Adds a pseudo to the allowlist. Returns false when it was already there.
    @discardableResult
    public func allow(_ pseudo: String) throws -> Bool {
        try mutate { document in try Self.insert(pseudo, into: &document.allowlist) }
    }

    /// Removes a pseudo from the allowlist. Returns false when it was not there.
    @discardableResult
    public func disallow(_ pseudo: String) throws -> Bool {
        try mutate { document in Self.remove(pseudo, from: &document.allowlist) }
    }

    // MARK: Recovery

    /// Reads the stored data again, for example after the user restored a file. Returns the failure if any.
    @discardableResult
    public func reload() -> PseudoListError? {
        state = .unloaded
        return loadFailure()
    }

    /// Sets the unreadable data aside (a `.corrupt` copy for files, never a deletion) and starts from empty lists.
    /// Only call it after the user agreed: this is the single way out of a failed load.
    public func discardUnreadableData() throws {
        guard case .failed = loadedState() else { return }
        do {
            try persistence.quarantineUnreadableData()
        } catch {
            throw PseudoListError.saveFailed(reason: String(describing: error))
        }
        state = .loaded(PseudoListDocument())
    }

    // MARK: Internals

    private var document: PseudoListDocument? {
        if case .loaded(let document) = loadedState() { return document }
        return nil
    }

    private func loadedState() -> State {
        if case .unloaded = state {
            do {
                let stored = try persistence.load() ?? PseudoListDocument()
                if stored.version > PseudoListDocument.currentVersion {
                    state = .failed(.unsupportedVersion(stored.version))
                } else {
                    state = .loaded(stored)
                }
            } catch {
                state = .failed(.loadFailed(reason: String(describing: error)))
            }
        }
        return state
    }

    /// Applies `change` to a copy, persists it, then publishes it: memory never gets ahead of the disk.
    private func mutate(_ change: (inout PseudoListDocument) throws -> Bool) throws -> Bool {
        switch loadedState() {
        case .failed(let error):
            throw error
        case .unloaded:
            throw PseudoListError.loadFailed(reason: "unreachable state")
        case .loaded(let current):
            var updated = current
            guard try change(&updated) else { return false }
            do {
                try persistence.save(updated)
            } catch {
                throw PseudoListError.saveFailed(reason: String(describing: error))
            }
            state = .loaded(updated)
            return true
        }
    }

    private static func index(of pseudo: String, in list: [PseudoListEntry]) -> Int? {
        let target = PseudoNormalizer.normalize(pseudo)
        return list.firstIndex { PseudoNormalizer.normalize($0.pseudo) == target }
    }

    private static func insert(_ pseudo: String, into list: inout [PseudoListEntry]) throws -> Bool {
        guard !PseudoNormalizer.normalize(pseudo).isEmpty else { throw PseudoListError.emptyPseudo }
        guard index(of: pseudo, in: list) == nil else { return false }
        list.append(PseudoListEntry(pseudo: pseudo))
        return true
    }

    private static func remove(_ pseudo: String, from list: inout [PseudoListEntry]) -> Bool {
        guard let position = index(of: pseudo, in: list) else { return false }
        list.remove(at: position)
        return true
    }
}
