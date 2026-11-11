import HFRStorage

/// A store of one account's data on this device (ADR 0013 appendix), as the deletion screen names it (LOT-157).
enum AccountDataKind: CaseIterable, Hashable, Sendable {
    /// Unsent drafts (LOT-063).
    case drafts
    /// The account's blocklist, local copy (LOT-061).
    case blocklist
    /// Reading positions (LOT-090).
    case readingPositions
    /// Super-favourites (LOT-064).
    case superFavorites
    /// The app's own favourite smileys (LOT-064).
    case smileyFavorites
    /// Super-favourites and reply drafts the legacy import set aside for the account (LOT-158, `pending.json`).
    case legacyPending

    /// Name in a French sentence ("… n’ont pas pu être effacés : les brouillons").
    var title: String {
        switch self {
        case .drafts: "les brouillons"
        case .blocklist: "la liste noire"
        case .readingPositions: "les positions de lecture"
        case .superFavorites: "les super-favoris"
        case .smileyFavorites: "les smileys favoris"
        case .legacyPending: "les éléments en attente de l’ancienne app"
        }
    }
}

/// Erases one account's data from the app's per-account stores (LOT-157), never another account's entries.
///
/// Holds the stores themselves, so the live eraser is checked to write the same actors as the screens (one actor per file:
/// a second store over the same file would race them). The account itself (Keychain, session) is removed by
/// `AccountsModel.remove(_:)` and `removeStoreItemIfEmpty()`; stores that belong to no account (allowlist, histories,
/// offline topics, caches, settings) are not touched. `forget(account:)` tells the legacy import to skip the account from
/// then on, since legacy's Keychain item, which it only reads, still lists it; the model calls it first.
struct AccountDataEraser: Sendable {
    let drafts: DraftStore
    let pseudoLists: PseudoListStore
    let positions: ReadingPositionStore
    let superFavorites: SuperFavoritesStore
    let smileyFavorites: AppSmileyFavoritesStore
    let legacyPending: LegacyPendingStore
    /// The app's one importer (its runs and `forget` are serialized); nil where there is no legacy import.
    let legacyImport: LegacyImporter?

    /// The stores the app writes (`Application Support/`).
    static let live = AccountDataEraser(
        drafts: ComposerServices.liveDrafts,
        pseudoLists: PseudoListsSnapshot.liveStore,
        positions: LiveReaderPositionRecorder.store,
        superFavorites: FavoritesStores.shared.superFavorites,
        smileyFavorites: ComposerServices.liveSmileyFavorites,
        legacyPending: LegacyImportServices.livePending,
        legacyImport: LegacyImportServices.liveImporter
    )

    /// The account keys (`AccountKey`) that still have data in one of the stores; a store that cannot be read adds none.
    func accountKeys() async -> Set<String> {
        var keys = await drafts.accountKeys()
        keys.formUnion(await pseudoLists.blocklistAccountKeys())
        // Positions are stored under the account's spelling, not its key.
        keys.formUnion(await positions.accounts().map(AccountKey.make))
        keys.formUnion(await superFavorites.accountKeys())
        keys.formUnion(await smileyFavorites.accountKeys())
        keys.formUnion(await legacyPending.accountKeys())
        return keys
    }

    /// Records `account` in the legacy import's list of erased accounts (LOT-158 never brings it back), after any import run
    /// in progress. Called before the account is removed: removing the current account runs an incomplete import again.
    func forget(account: String) async throws {
        try await legacyImport?.forget(account: account)
    }

    /// Erases `kinds` of `account` (the account's pseudo or key). Every kind is tried even when an earlier one
    /// failed; returns the kinds that could not be erased, in order.
    func erase(account: String, kinds: [AccountDataKind] = AccountDataKind.allCases) async -> [AccountDataKind] {
        var failed: [AccountDataKind] = []
        for kind in kinds {
            do {
                try await erase(kind, account: account)
            } catch {
                failed.append(kind)
            }
        }
        return failed
    }

    private func erase(_ kind: AccountDataKind, account: String) async throws {
        switch kind {
        case .drafts:
            _ = try await drafts.discardAll(account: account)
        case .blocklist:
            // An empty list removes the account's key from the document.
            _ = try await pseudoLists.replaceBlocklist(with: [], account: account)
        case .readingPositions:
            // Stored under the spelling the reader used: remove every spelling of the account's key.
            // An unreadable store lists no account: report it instead of a success.
            if let failure = await positions.loadFailure() { throw failure }
            let key = AccountKey.make(account)
            for stored in await positions.accounts() where AccountKey.make(stored) == key {
                _ = try await positions.removeAccount(stored)
            }
        case .superFavorites:
            _ = try await superFavorites.replace([], account: account)
        case .smileyFavorites:
            _ = try await smileyFavorites.replace([], account: account)
        case .legacyPending:
            try await legacyPending.discardAll(account: account)
        }
    }
}
