import Foundation
import HFRModels

/// Where the legacy app's data is read (Q-1: same bundle, same container). Read only, except the page cache.
public struct LegacyContainer: Sendable {
    /// The app's `Documents` folder (legacy `NSDocumentDirectory`, last path).
    public var documentsDirectory: URL
    /// The app's `Library/Caches` folder (legacy `NSCachesDirectory`).
    public var cachesDirectory: URL
    /// The legacy `UserDefaults` standard suite, read only.
    public var defaults: any LegacyDefaults
    /// The legacy Keychain accounts.
    public var accounts: any LegacyAccountSource

    /// Creates a container description.
    public init(documentsDirectory: URL, cachesDirectory: URL, defaults: any LegacyDefaults, accounts: any LegacyAccountSource) {
        self.documentsDirectory = documentsDirectory
        self.cachesDirectory = cachesDirectory
        self.defaults = defaults
        self.accounts = accounts
    }
}

/// The SwiftHFR stores the import writes into, each through its public API (so its guards and atomic saves apply).
public struct LegacyImportDestinations: Sendable {
    /// Accounts (LOT-065).
    public var credentials: any CredentialStore
    /// Blocklists and allowlist (LOT-061).
    public var pseudoLists: PseudoListStore
    /// Super-favourites (LOT-064), filled through `pending`.
    public var superFavorites: SuperFavoritesStore
    /// Collapsed favourites sections (LOT-064).
    public var layout: FavoritesLayoutStore
    /// App smiley favourites (LOT-064).
    public var smileyFavorites: AppSmileyFavoritesStore
    /// Smiley search history (LOT-064).
    public var searchHistory: SmileySearchHistoryStore
    /// Rehost upload history (LOT-064).
    public var uploads: RehostUploadHistoryStore
    /// Drafts (LOT-063).
    public var drafts: DraftStore
    /// Super-favourites and reply drafts waiting to be placed (decisions D1, D2).
    public var pending: LegacyPendingStore
    /// The settings suite (LOT-060), where `mpstorage_active` is read.
    public var settings: any SettingsStore

    /// Creates the destinations.
    public init(
        credentials: any CredentialStore,
        pseudoLists: PseudoListStore,
        superFavorites: SuperFavoritesStore,
        layout: FavoritesLayoutStore,
        smileyFavorites: AppSmileyFavoritesStore,
        searchHistory: SmileySearchHistoryStore,
        uploads: RehostUploadHistoryStore,
        drafts: DraftStore,
        pending: LegacyPendingStore,
        settings: any SettingsStore
    ) {
        self.credentials = credentials
        self.pseudoLists = pseudoLists
        self.superFavorites = superFavorites
        self.layout = layout
        self.smileyFavorites = smileyFavorites
        self.searchHistory = searchHistory
        self.uploads = uploads
        self.drafts = drafts
        self.pending = pending
        self.settings = settings
    }
}

/// Imports the legacy app's on-device data into the SwiftHFR stores, once per step (LOT-067, ADR 0013 §5).
///
/// The app runs it at launch and after each login (LOT-158) until the report is complete. A step is marked done only
/// after its destination saved, and never runs again; a failed step runs at the next call. Data already in a SwiftHFR
/// store wins over the legacy copy. Nothing in the legacy container is written or deleted, except the rendered page
/// cache. Nothing is logged; the report holds counts only.
public actor LegacyImporter {
    let container: LegacyContainer
    let destinations: LegacyImportDestinations
    private var state: SmallStoreState<LegacyImportStateDocument>
    /// The SwiftHFR pseudo of the legacy main account, set by the accounts step of this run.
    var legacyMainAccount: String?
    /// The run in progress: runs are serialized, so two overlapping calls (launch, login) never save over each other.
    private var currentRun: Task<LegacyImportReport, Never>?

    /// Creates an importer; `state` holds what was done on this device (`migration.legacyImport.version`).
    public init(
        container: LegacyContainer,
        destinations: LegacyImportDestinations,
        state: any SmallStorePersistence<LegacyImportStateDocument>
    ) {
        self.container = container
        self.destinations = destinations
        self.state = SmallStoreState(persistence: state)
    }

    /// Runs every step not done yet. `currentAccount` is the pseudo of the account logged in now: it receives the
    /// legacy app's global items when legacy had no main account (decision D3).
    public func run(currentAccount: String? = nil, now: Date = .now) async -> LegacyImportReport {
        let previous = currentRun
        let task = Task {
            _ = await previous?.value
            return await self.runSteps(currentAccount: currentAccount, now: now)
        }
        currentRun = task
        return await task.value
    }

    private func runSteps(currentAccount: String?, now: Date) async -> LegacyImportReport {
        var report = LegacyImportReport()
        guard let stored = state.document() else {
            for step in LegacyImportStep.allCases { report.outcomes[step] = .failed(.destinationFailed) }
            return report
        }
        var current = stored
        if current.globalAccount == nil, current.done.contains(.accounts) {
            current.globalAccount = Self.cleanedAccount(currentAccount)
        }
        for step in LegacyImportStep.allCases {
            if current.done.contains(step) {
                report.outcomes[step] = .alreadyDone
                continue
            }
            if let waiting = Self.prerequisite(of: step, in: current) {
                report.outcomes[step] = waiting
                continue
            }
            report.outcomes[step] = await runStep(step, state: &current, currentAccount: currentAccount, now: now, report: &report)
        }
        if current != stored { _ = save(current) }
        report.mpStorageSwitch = current.mpStorageSwitch
        return report
    }

    // MARK: Internals

    private func perform(
        _ step: LegacyImportStep,
        globalAccount: String?,
        now: Date,
        report: inout LegacyImportReport
    ) async -> LegacyImportOutcome {
        let account = globalAccount ?? ""
        switch step {
        case .accounts: return await importAccounts(report: &report)
        case .pseudoLists: return await importPseudoLists(globalAccount: globalAccount, report: &report)
        case .superFavorites: return await importSuperFavorites(account: account, now: now)
        case .collapsedSections: return await importCollapsedSections()
        case .smileyFavorites: return await importSmileyFavorites(account: account, report: &report)
        case .smileySearchHistory: return await importSearchHistory()
        case .uploadHistory: return await importUploadHistory()
        case .drafts: return await importDrafts(account: account, now: now)
        case .mpStorageSwitch: return importMPStorageSwitch(report: &report)
        case .pageCache: return clearPageCache()
        }
    }

    /// The account logged in now, when the accounts step found no legacy main account (decision D3).
    private static func cleanedAccount(_ pseudo: String?) -> String? {
        let cleaned = pseudo.map(PseudoNormalizer.cleaned) ?? ""
        return cleaned.isEmpty ? nil : cleaned
    }

    /// Runs one step and, when it is done, records it in `state` once the state is saved.
    private func runStep(
        _ step: LegacyImportStep,
        state current: inout LegacyImportStateDocument,
        currentAccount: String?,
        now: Date,
        report: inout LegacyImportReport
    ) async -> LegacyImportOutcome {
        let outcome = await perform(step, globalAccount: current.globalAccount, now: now, report: &report)
        if step == .accounts, outcome.isDone, current.globalAccount == nil {
            current.globalAccount = legacyMainAccount ?? Self.cleanedAccount(currentAccount)
        }
        guard outcome.isDone else { return outcome }
        var updated = current
        updated.done = Set(current.done).union([step]).sorted()
        if step == .mpStorageSwitch { updated.mpStorageSwitch = report.mpStorageSwitch }
        guard save(updated) else { return .failed(.destinationFailed) }
        current = updated
        return outcome
    }

    /// Why a step cannot run yet: the global items wait for an account (D3); the pseudo lists wait for the accounts
    /// step, whose stored accounts tell under which pseudo a list keyed by a display name goes.
    private static func prerequisite(of step: LegacyImportStep, in document: LegacyImportStateDocument) -> LegacyImportOutcome? {
        if step == .pseudoLists, !document.done.contains(.accounts) { return .waitingForAccount }
        if step.needsGlobalAccount, document.globalAccount == nil { return .waitingForAccount }
        return nil
    }

    private func save(_ updated: LegacyImportStateDocument) -> Bool {
        do {
            _ = try state.mutate { document in
                guard updated != document else { return false }
                document = updated
                return true
            }
            return true
        } catch {
            return false
        }
    }
}
