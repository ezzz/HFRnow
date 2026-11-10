import Foundation
import HFRModels
import HFRStorage

// Port of none @ 87fe0d1c: legacy was the app this update replaces and never imported its data (GAP-170, new UX: spec).
/// The live legacy import (LOT-158): the importer over the app's own container and over the app's single store of each file.
enum LegacyImportServices {
    /// The super-favourites and reply drafts the import set aside (LOT-067 D1, D2): one actor for the file, shared by the
    /// importer, the favourites list and the reader.
    static let livePending = LegacyPendingStore(
        persistence: FileSmallStorePersistence(fileURL: folder.appending(path: "pending.json"))
    )

    /// The importer of this process. Legacy and SwiftHFR share the bundle (Q-1): the legacy data is in this container.
    static func liveImporter() -> LegacyImporter {
        let bundleID = Bundle.main.bundleIdentifier ?? "hfrplus.red.super"
        return LegacyImporter(
            container: LegacyContainer(
                documentsDirectory: URL.documentsDirectory,
                cachesDirectory: URL.cachesDirectory,
                defaults: UserDefaultsLegacyDefaults(),
                accounts: KeychainLegacyAccountSource(service: bundleID)
            ),
            destinations: LegacyImportDestinations(
                // The item `AccountsModel.live()` reads; the store keeps no state between calls.
                credentials: KeychainCredentialStore(service: bundleID),
                pseudoLists: PseudoListsSnapshot.liveStore,
                superFavorites: FavoritesStores.shared.superFavorites,
                layout: FavoritesStores.shared.layout,
                smileyFavorites: ComposerServices.liveSmileyFavorites,
                searchHistory: ComposerServices.liveSmileySearchHistory,
                uploads: ImageUploadServices.liveHistory.store,
                drafts: ComposerServices.liveDrafts,
                pending: livePending,
                settings: UserDefaultsSettingsStore()
            ),
            // `migration.legacyImport.version` (ADR 0013 appendix F), device-only.
            state: FileSmallStorePersistence(fileURL: folder.appending(path: "state.json"))
        )
    }

    private static var folder: URL {
        URL.applicationSupportDirectory.appending(path: "LegacyImport", directoryHint: .isDirectory)
    }
}

/// Places the legacy reply draft of a topic, left pending by the import, into that topic's reply draft for one account
/// (LOT-067 D1): called when the reader opens the topic and before the reply composer reads its draft.
struct LegacyDraftResolver: Sendable {
    let pending: LegacyPendingStore
    let drafts: DraftStore
    /// The current account's key (`md_user` value).
    let account: String

    /// The resolver of `account` over the live stores; nil when logged out (no composer, no draft).
    static func live(account: String?) -> LegacyDraftResolver? {
        account.map { LegacyDraftResolver(pending: LegacyImportServices.livePending, drafts: ComposerServices.liveDrafts, account: $0) }
    }

    /// Turns the pending draft of `topic`'s number into its reply draft, unless that draft exists (the SwiftHFR one wins).
    func resolve(_ topic: TopicID) async {
        // A failure keeps the draft pending (LOT-067) and the next opening tries again; a draft store that cannot be read
        // is reported by the composer itself when it reads the draft (LOT-084), so nothing is shown here.
        _ = try? await pending.resolveReplyDraft(for: ReplyTarget.draftContext(of: topic), account: account, into: drafts)
    }
}
