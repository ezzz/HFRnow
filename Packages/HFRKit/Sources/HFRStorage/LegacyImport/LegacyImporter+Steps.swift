import Foundation
import HFRModels

extension LegacyImporter {
    // MARK: Accounts and lists

    /// Step 1: the legacy accounts into LOT-065, keeping an account SwiftHFR already stores (its cookies are newer).
    /// The legacy main account becomes main only when SwiftHFR stored no account before.
    func importAccounts(report: inout LegacyImportReport) async -> LegacyImportOutcome {
        let records: [LegacyAccountRecord]
        do {
            records = try container.accounts.accounts()
        } catch {
            return .failed(error)
        }
        guard !records.isEmpty else { return .nothingToImport }
        // Legacy's main account is the last one flagged (`getMainCompte`, `MultisManager.m:168-176`).
        let mainPseudo = records.last { $0.isMain }?.pseudo
        // An account erased from this device (LOT-157) is not brought back; when it was legacy's main account, the global
        // items stay its own (skipped by their steps), not given to the account logged in now.
        let erased = erasedKeys ?? []
        let isErased = { (pseudo: String?) in pseudo.map { erased.contains(ErasedAccountsEnvelope.key($0)) } ?? false }
        let kept = records.filter { !isErased($0.pseudo) }
        let erasedMain = isErased(mainPseudo) ? mainPseudo.map(PseudoNormalizer.cleaned) : nil
        do {
            let result = try container.credentialsUpdate(destinations.credentials, kept, erasedMain == nil ? mainPseudo : nil)
            report.rejectedItems += result.rejected
            legacyMainAccount = erasedMain ?? result.mainPseudo
            return result.imported > 0 ? .imported(result.imported) : .nothingToImport
        } catch {
            return .failed(.destinationFailed)
        }
    }

    /// Step 2: `blackListDico.plist` (or the v0 `blackList.plist` when it is absent) and `whiteList.plist`. Each file is
    /// read on its own, as legacy did (`BlackList.m:173-202`): an unreadable one counts as empty and the other is still
    /// imported; the step reports `sourceUnreadable` only when nothing readable was found.
    func importPseudoLists(globalAccount: String?, report: inout LegacyImportReport) async -> LegacyImportOutcome {
        var unreadable = false
        let lists: [String: [String]]
        switch legacyBlocklists(globalAccount: globalAccount) {
        case .success(let value): lists = value
        case .failure(let outcome) where outcome.value == .failed(.sourceUnreadable):
            lists = [:]
            unreadable = true
        case .failure(let outcome): return outcome.value
        }
        var allowlist: [String] = []
        switch readPlist(container.documentsDirectory.appending(path: LegacyKeys.allowlistFile)) {
        case .failure(.sourceUnreadable): unreadable = true
        case .failure(let error): return .failed(error)
        case .success(nil): break
        case .success(let value?):
            if let entries = LegacyFormats.pseudoList(value) { allowlist = entries } else { unreadable = true }
        }
        guard !lists.isEmpty || !allowlist.isEmpty else { return unreadable ? .failed(.sourceUnreadable) : .nothingToImport }
        return await writePseudoLists(lists, allowlist: allowlist, report: &report)
    }

    /// The legacy blocklists by account name: the dictionary file, else the v0 array given to the main account
    /// (`BlackList.m:184-190`), else none.
    private func legacyBlocklists(globalAccount: String?) -> Result<[String: [String]], OutcomeError> {
        let documents = container.documentsDirectory
        switch readPlist(documents.appending(path: LegacyKeys.blocklistFile)) {
        case .failure(let error): return .failure(OutcomeError(.failed(error)))
        case .success(let value?):
            guard let decoded = LegacyFormats.blocklists(value) else { return .failure(OutcomeError(.failed(.sourceUnreadable))) }
            return .success(decoded)
        case .success(nil): break
        }
        switch readPlist(documents.appending(path: LegacyKeys.blocklistV0File)) {
        case .failure(let error): return .failure(OutcomeError(.failed(error)))
        case .success(nil): return .success([:])
        case .success(let value?):
            guard let legacyList = LegacyFormats.pseudoList(value) else { return .failure(OutcomeError(.failed(.sourceUnreadable))) }
            guard let globalAccount else { return .failure(OutcomeError(.waitingForAccount)) }
            return .success([globalAccount: legacyList])
        }
    }

    private func writePseudoLists(_ lists: [String: [String]], allowlist: [String], report: inout LegacyImportReport) async
        -> LegacyImportOutcome {
        let book: AccountBook
        do {
            book = try destinations.credentials.load()
        } catch {
            return .failed(.destinationFailed)
        }
        let erased = erasedListNames()
        var imported = 0
        do {
            for (name, pseudos) in lists.sorted(by: { $0.key < $1.key }) {
                // Legacy keyed lists by display name (`BlackList.m:91-103`): file them under the account's pseudo.
                let account = book.account(matching: name)?.pseudo ?? name
                // The blocklist of an account erased from this device is not brought back (LOT-157).
                if erased.contains(ErasedAccountsEnvelope.key(account)) { continue }
                for pseudo in pseudos {
                    imported += try await added(report: &report) { try await $0.block(pseudo, account: account) }
                }
            }
            for pseudo in allowlist {
                imported += try await added(report: &report) { try await $0.allow(pseudo) }
            }
        } catch {
            return .failed(.destinationFailed)
        }
        return imported > 0 ? .imported(imported) : .nothingToImport
    }

    /// The keys an erased account's legacy list can be filed under: its pseudo, and its legacy display name (legacy keyed
    /// lists by display name, and an erased account is no longer in the book to translate it).
    private func erasedListNames() -> Set<String> {
        var names = erasedKeys ?? []
        for record in (try? container.accounts.accounts()) ?? [] {
            guard let pseudo = record.pseudo, names.contains(ErasedAccountsEnvelope.key(pseudo)) else { continue }
            if let name = record.displayName { names.insert(ErasedAccountsEnvelope.key(name)) }
        }
        return names
    }

    /// 1 when the store added the pseudo, 0 when it was there; an empty pseudo is counted as rejected.
    private func added(
        report: inout LegacyImportReport,
        _ write: (PseudoListStore) async throws -> Bool
    ) async throws -> Int {
        do {
            return try await write(destinations.pseudoLists) ? 1 : 0
        } catch PseudoListError.emptyPseudo {
            report.rejectedItems += 1
            return 0
        }
    }

    // MARK: Small stores

    /// Step 3: legacy super-favourite numbers set aside until the favourites list gives their category (D2).
    func importSuperFavorites(account: String, now: Date) async -> LegacyImportOutcome {
        let numbers = LegacyFormats.superFavoriteNumbers(container.defaults.value(forKey: LegacyKeys.superFavorites))
        guard !numbers.isEmpty else { return .nothingToImport }
        do {
            let added = try await destinations.pending.addSuperFavorites(numbers, account: account, at: now)
            return added > 0 ? .imported(added) : .nothingToImport
        } catch {
            return .failed(.destinationFailed)
        }
    }

    /// Step 4: collapsed favourites sections.
    func importCollapsedSections() async -> LegacyImportOutcome {
        let sections = LegacyFormats.collapsedSections(container.defaults.value(forKey: LegacyKeys.collapsedSections))
        guard !sections.isEmpty else { return .nothingToImport }
        var imported = 0
        do {
            for section in sections where try await destinations.layout.setCollapsed(true, section: section) {
                imported += 1
            }
        } catch {
            return .failed(.destinationFailed)
        }
        return imported > 0 ? .imported(imported) : .nothingToImport
    }

    /// Step 5: app smiley favourites, oldest first, with their legacy dates.
    func importSmileyFavorites(account: String, report: inout LegacyImportReport) async -> LegacyImportOutcome {
        let data: Data
        switch readFile(container.documentsDirectory.appending(path: LegacyKeys.smileyFavoritesFile)) {
        case .failure(let error): return .failed(error)
        case .success(nil): return .nothingToImport
        case .success(let bytes?): data = bytes
        }
        guard let favorites = LegacyFormats.smileyFavorites(data) else { return .failed(.sourceUnreadable) }
        var imported = 0
        for favorite in favorites {
            guard let url = URL(string: favorite.url) else { continue }
            do {
                if try await destinations.smileyFavorites.add(code: favorite.code, url: url, account: account, at: favorite.addedAt) {
                    imported += 1
                }
            } catch SmallStoreError.invalidValue {
                // A blank code: legacy could not have used it either; the next favourites still go in.
                report.rejectedItems += 1
            } catch {
                return .failed(.destinationFailed)
            }
        }
        return imported > 0 ? .imported(imported) : .nothingToImport
    }

    /// Step 6: the smiley search history with its counts and dates.
    func importSearchHistory() async -> LegacyImportOutcome {
        let value = container.defaults.value(forKey: LegacyKeys.smileySearchHistory)
        guard value != nil else { return .nothingToImport }
        guard let entries = LegacyFormats.searchHistory(value) else { return .failed(.sourceUnreadable) }
        do {
            let added = try await destinations.searchHistory.merge(entries)
            return added > 0 ? .imported(added) : .nothingToImport
        } catch {
            return .failed(.destinationFailed)
        }
    }

    /// Step 7: the upload history, added oldest first so the store's newest-first order is the legacy file's.
    func importUploadHistory() async -> LegacyImportOutcome {
        let data: Data
        switch readFile(container.documentsDirectory.appending(path: LegacyKeys.uploadHistoryFile)) {
        case .failure(let error): return .failed(error)
        case .success(nil): return .nothingToImport
        case .success(let bytes?): data = bytes
        }
        guard let images = LegacyFormats.uploadHistory(data) else { return .failed(.sourceUnreadable) }
        var imported = 0
        do {
            for image in images.reversed() where try await destinations.uploads.add(image) {
                imported += 1
            }
        } catch {
            return .failed(.destinationFailed)
        }
        return imported > 0 ? .imported(imported) : .nothingToImport
    }

    // MARK: Drafts, switch, cache

    /// Step 8 (D1): `brouillon` into `.legacyGlobal` unless one exists; the Swift composer's active drafts set aside
    /// until their topic opens. Archived drafts (`reply_drafts_by_topic_v1`) are not imported.
    func importDrafts(account: String, now: Date) async -> LegacyImportOutcome {
        var imported = 0
        do {
            if case .string(let text) = container.defaults.value(forKey: LegacyKeys.objcDraft),
               !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
               await destinations.drafts.draft(for: .legacyGlobal, account: account) == nil {
                try await destinations.drafts.save(text, for: .legacyGlobal, account: account)
                imported += 1
            }
            let active = LegacyFormats.activeDrafts(container.defaults.value(forKey: LegacyKeys.activeReplyDrafts)) ?? []
            let pending = active.map { PendingReplyDraft(number: $0.topicNumber, text: $0.text, updatedAt: $0.updatedAt) }
            if !pending.isEmpty {
                imported += try await destinations.pending.addReplyDrafts(pending, account: account, at: now)
            }
        } catch {
            return .failed(.destinationFailed)
        }
        return imported > 0 ? .imported(imported) : .nothingToImport
    }

    /// Step 9: `mpstorage_active` read once for LOT-130 (ADR 0013 §7); never written.
    func importMPStorageSwitch(report: inout LegacyImportReport) -> LegacyImportOutcome {
        guard destinations.settings.rawValue(forKey: SettingKey.mpStorageActive.key) != nil else { return .nothingToImport }
        report.mpStorageSwitch = destinations.settings.value(for: SettingKey.mpStorageActive) ? .active : .inactive
        return .imported(1)
    }

    /// Step 10: the legacy rendered pages of `Caches/cache`.
    func clearPageCache() -> LegacyImportOutcome {
        let result = LegacyPageCache.removePages(cachesDirectory: container.cachesDirectory)
        if result.failed > 0 { return .failed(.sourceUnavailable) }
        return result.removed > 0 ? .imported(result.removed) : .nothingToImport
    }

    // MARK: Reading files

    /// The bytes of a legacy file; nil when it does not exist (never follows a missing file into an error).
    private func readFile(_ url: URL) -> Result<Data?, LegacyImportError> {
        guard FileManager.default.fileExists(atPath: url.path(percentEncoded: false)) else { return .success(nil) }
        do {
            return .success(try Data(contentsOf: url))
        } catch {
            return .failure(.sourceUnavailable)
        }
    }

    /// A legacy plist file parsed; nil when absent, `sourceUnreadable` when it is not a plist.
    private func readPlist(_ url: URL) -> Result<LegacyValue?, LegacyImportError> {
        switch readFile(url) {
        case .failure(let error): return .failure(error)
        case .success(nil): return .success(nil)
        case .success(let data?):
            guard let value = LegacyValue.parse(data) else { return .failure(.sourceUnreadable) }
            return .success(value)
        }
    }
}

/// An outcome carried through a `Result` failure.
struct OutcomeError: Error {
    let value: LegacyImportOutcome

    init(_ value: LegacyImportOutcome) {
        self.value = value
    }
}

/// What the accounts step wrote.
struct AccountsImport {
    var imported = 0
    var rejected = 0
    /// The SwiftHFR pseudo of the legacy main account, when it was stored.
    var mainPseudo: String?
}

extension LegacyContainer {
    /// Adds the legacy accounts to `store` in one update.
    func credentialsUpdate(
        _ store: any CredentialStore,
        _ records: [LegacyAccountRecord],
        _ mainPseudo: String?
    ) throws -> AccountsImport {
        try store.update { book in
            let wasEmpty = book.accounts.isEmpty
            var result = AccountsImport()
            for record in records {
                guard let pseudo = record.pseudo, !pseudo.isEmpty else {
                    result.rejected += 1
                    continue
                }
                guard book.account(matching: pseudo) == nil else { continue }
                let account = Account(
                    pseudo: pseudo,
                    displayName: record.displayName,
                    cookies: record.cookies,
                    hashCheck: record.hashCheck,
                    avatarData: record.avatarData
                )
                do {
                    try book.add(account, makeMain: false)
                    result.imported += 1
                } catch {
                    result.rejected += 1
                }
            }
            result.mainPseudo = mainPseudo.flatMap { book.account(matching: $0)?.pseudo }
            if wasEmpty, let main = result.mainPseudo { _ = book.setMain(pseudo: main) }
            return result
        }
    }
}
