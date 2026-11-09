import Foundation
import HFRStorage

/// Which of the two pseudo lists an editor, a menu entry or a profile button works on.
enum PseudoListKind: Equatable, Sendable {
    /// The account's blocklist ("Liste noire"), kept per account.
    case blocklist
    /// The global allowlist ("Love list" in the menus, "Liste blanche" in Réglages, as legacy).
    case allowlist

    /// Screen title (`ProfileFilterListKind.title`, `AppSettingsView.swift:553-560` @ 2440d79).
    var title: String { self == .blocklist ? "Liste noire" : "Liste blanche" }
    /// Shown when the list is empty (`emptyMessage`, `:562-569`).
    var emptyMessage: String { self == .blocklist ? "Aucun pseudo blacklisté." : "Aucun pseudo whitelisté." }
    /// Footer of the list (`footer`, `:571-578`).
    var footer: String {
        switch self {
        case .blocklist: "La liste noire est liée au compte actif."
        case .allowlist: "La liste blanche est globale : elle sert aux citations, aux messages et au filtre des posts."
        }
    }
    /// Legacy's error text for an add that failed (`addProfile`, `:668-678`).
    var addFailure: String { "Impossible d'ajouter ce pseudo à la \(self == .blocklist ? "liste noire" : "liste blanche")." }
    /// Legacy's error text for a removal that failed (`removeProfiles`, `:684-696`).
    func removeFailure(_ pseudo: String) -> String {
        "Impossible de supprimer \(pseudo) de la \(self == .blocklist ? "liste noire" : "liste blanche")."
    }
}

/// What a toggle from the message menu or the profile did, with the sentence to show.
struct PseudoListToggleResult: Equatable, Sendable {
    /// The toast text (legacy's, `Common.swift:963-989` @ 2440d79).
    let message: String
    /// The list changed, so the page on screen must be rebuilt.
    let changed: Bool
}

// Port of HFRswift/Swift/Common.swift (ObjCProfileFilterListManager: add, remove, toggleBlacklist, toggleWhitelist) @ 2440d79.
// Differences: it writes to LOT-117's `PseudoListStore` (the one actor over the file, never a second one), which cleans and
// compares pseudos by the LOT-072 rule; a store that cannot be read refuses writes instead of overwriting the file (audit E §7.2);
// the toggle of the allowlist reads the allowlist itself, not "allowed and not blocked".
/// The app's one entry point to edit the pseudo lists: the two editors of Réglages, the BL / WL entries of the message menu and
/// the profile buttons use it. Every write refreshes the reader's snapshot afterwards, so the next page build reads the change.
struct PseudoListManager: Sendable {
    private let store: PseudoListStore
    /// The current account's key, nil when logged out (then only the allowlist can be edited).
    let account: String?
    private let snapshot: PseudoListsSnapshot?

    /// A manager over `store` for `account`; `snapshot` is refreshed after each write.
    init(store: PseudoListStore, account: String?, snapshot: PseudoListsSnapshot? = nil) {
        self.store = store
        self.account = account
        self.snapshot = snapshot
    }

    /// Whether `pseudo` is the current account's own pseudo (never offered for the lists, as legacy's `isOwnMessage`).
    func isOwn(_ pseudo: String) -> Bool { account.map { PseudoNormalizer.matches($0, pseudo) } ?? false }

    /// Whether `kind` can be edited: the blocklist belongs to an account.
    func isAvailable(_ kind: PseudoListKind) -> Bool { kind == .allowlist || account != nil }

    /// The pseudos of `kind`, sorted as legacy's editors (case-insensitive, `reloadProfiles`, `:658-662`). Empty when the store
    /// cannot be read: `loadFailure()` says so.
    func pseudos(of kind: PseudoListKind) async -> [String] {
        let entries: [PseudoListEntry]
        switch kind {
        case .blocklist:
            if let account { entries = await store.blocklist(for: account) } else { entries = [] }
        case .allowlist: entries = await store.allowlist()
        }
        return entries.map(\.pseudo).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// Why the lists cannot be written, nil when they can.
    func loadFailure() async -> PseudoListError? { await store.loadFailure() }

    /// Reads the stored lists again, after the user restored the file.
    func reload() async -> PseudoListError? { await store.reload() }

    /// Whether `pseudo` is in the list.
    func contains(_ pseudo: String, in kind: PseudoListKind) async -> Bool {
        await pseudos(of: kind).contains { PseudoNormalizer.matches($0, pseudo) }
    }

    /// Adds `pseudo`; false when it already was there. Throws the store's refusal (empty pseudo, unreadable file, save failed).
    @discardableResult
    func add(_ pseudo: String, to kind: PseudoListKind) async throws -> Bool {
        let added: Bool
        switch kind {
        case .blocklist:
            guard let account else { throw PseudoListError.loadFailed(reason: "logged out") }
            added = try await store.block(pseudo, account: account)
        case .allowlist: added = try await store.allow(pseudo)
        }
        if added { await snapshot?.refresh() }
        return added
    }

    /// Removes `pseudo`; false when it was not there.
    @discardableResult
    func remove(_ pseudo: String, from kind: PseudoListKind) async throws -> Bool {
        let removed: Bool
        switch kind {
        case .blocklist:
            guard let account else { throw PseudoListError.loadFailed(reason: "logged out") }
            removed = try await store.unblock(pseudo, account: account)
        case .allowlist: removed = try await store.disallow(pseudo)
        }
        if removed { await snapshot?.refresh() }
        return removed
    }

    /// The menu / profile action: removes `pseudo` when it is in the list, adds it otherwise, and says what happened in legacy's
    /// words. A pseudo that is empty once cleaned does nothing (nil, legacy's `toggle…` returned nil too).
    func toggle(_ pseudo: String, in kind: PseudoListKind) async -> PseudoListToggleResult? {
        let name = PseudoNormalizer.cleaned(pseudo)
        guard !PseudoNormalizer.comparisonForm(name).isEmpty else { return nil }
        let removing = await contains(name, in: kind)
        do {
            // The check and the write are two hops: a concurrent change (double tap, iCloud) makes the write a no-op, and the page
            // is then left alone.
            if removing {
                let changed = try await remove(name, from: kind)
                return PseudoListToggleResult(message: Self.removed(name, kind), changed: changed)
            }
            let changed = try await add(name, to: kind)
            return PseudoListToggleResult(message: Self.added(name, kind), changed: changed)
        } catch {
            return PseudoListToggleResult(message: Self.failed(name, kind, removing: removing), changed: false)
        }
    }

    // Legacy's sentences, `toggleBlacklist` and `toggleWhitelist` (`Common.swift:963-989`); the whitelist has none for a failed
    // add (legacy returned nil, and the caller said "Whitelist impossible", `MessagesView.swift:3678-3684`).
    private static func removed(_ name: String, _ kind: PseudoListKind) -> String {
        kind == .blocklist ? "\(name) a été supprimé de la liste noire" : "OH NOES ! \(name) a été supprimé de la love list"
    }

    private static func added(_ name: String, _ kind: PseudoListKind) -> String {
        kind == .blocklist ? "BIM! \(name) ajouté à la liste noire" : "BOUM BOUM ! \(name) ajouté à la love list \u{2665}"
    }

    private static func failed(_ name: String, _ kind: PseudoListKind, removing: Bool) -> String {
        guard kind == .blocklist else { return "Whitelist impossible" }
        return "Erreur! \(name) n'a pas pu être \(removing ? "supprimé de" : "ajouté à") la liste noire"
    }
}
