import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRStorage
import Observation

// Port of HFRswift/Swift/AppSettingsView.swift (handleMPStorageToggle, reloadMPStorage) and Classes/MPStorage.m
// (initOrResetMP:fromView:) @ 87fe0d1c. Differences: one state per HFR account, on by itself when the account already has
// a storage thread, the creation question asked when switching on or at the first write, never at launch (GAP-181,
// ADR 0013 §7); edits are local first and merged (GAP-182, GAP-183); "Dernier accès" is persisted per account.
/// MPStorage sync of the current account (LOT-130): its state record, its device copy and the sync loop. One model per
/// account session (`RootModel`), so no account's state or document ever shows under another.
@MainActor
@Observable
final class MPStorageSyncModel {
    /// What the model is doing.
    enum Status: Equatable {
        case idle
        case working
        /// The last call failed: why, in French, without document text or pseudos.
        case failed(String)
    }

    /// What a bookmark or blacklist write does (LOT-131, LOT-132 call `writeConsent(for:)` before it).
    enum WriteConsent: Equatable {
        /// The account syncs: edit through `edit(_:_:)`.
        case sync
        /// The list stays on the device (declined, off, unreadable state).
        case deviceOnly
        /// No choice yet: ask, then `answerCreation(_:)`.
        case ask
    }

    /// The legacy question (`MPStorage.m:91`), asked before the thread is created.
    static let creationQuestion = "Le MP de stockage n'a pas été trouvé. Voulez-vous qu'il soit créé ?"
    /// How long a search that found no thread is trusted before `start()` searches again: the search walks the MP list.
    static let searchInterval: TimeInterval = 86_400

    /// `md_user` of the account.
    let account: String
    /// The account's record; nil when the stored value is unreadable (written by a newer build).
    private(set) var record: MPStorageSyncRecord?
    /// The last successful read or write on this device.
    private(set) var lastSync: Date?
    private(set) var status = Status.idle
    /// True once a sync found no storage thread (deleted elsewhere): switching on again asks to create one.
    private(set) var threadMissing = false
    /// True while the creation question waits for an answer.
    var asksCreation = false
    /// The document shown (local edits included), for the MP list flags; nil before the first read.
    private(set) var document: MPStorageDocument?

    @ObservationIgnored private let sync: MPStorageSync
    @ObservationIgnored private let states: MPStorageSyncStateStore
    @ObservationIgnored private let isLoggedIn: @Sendable () async -> Bool
    @ObservationIgnored private let clock: @Sendable () -> Date
    @ObservationIgnored private var started = false
    /// Whether the last failure was the network's: only then does `start()` run again at the next appearance.
    @ObservationIgnored private var lastFailureWasNetwork = false

    /// Creates the model; nothing is read or fetched before `start()`.
    init(
        account: String, sync: MPStorageSync, states: MPStorageSyncStateStore,
        isLoggedIn: @escaping @Sendable () async -> Bool, clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.account = account
        self.sync = sync
        self.states = states
        self.isLoggedIn = isLoggedIn
        self.clock = clock
        record = states.record(for: account)
    }

    /// The model of `account` over its session, the app's settings store and the device copies.
    static func live(account: String, session: HFRSession, settings: any SettingsStore) -> MPStorageSyncModel {
        MPStorageSyncModel(
            account: account,
            sync: MPStorageSync(
                remote: LiveMPStorageRemote(session: session),
                persistence: MPStorageCopyPersistence(store: MPStorageCopyPersistence.liveStore, account: account)
            ),
            states: MPStorageSyncStateStore(settings: settings),
            isLoggedIn: { await session.isLoggedIn() }
        )
    }

    /// Whether sync runs for the account.
    var isOn: Bool { record?.state == .on }

    /// Appearance of the Messages tab or Réglages, once per model; after a network failure it runs again at the next
    /// appearance, as legacy reloaded at each MP list load (`HFRMPViewController.m:32-36`), never after a search that hit its
    /// limit or found no thread (each run would walk the MP list again: the flood limit is shared). The copy is shown, then `on`
    /// syncs and `unasked` looks for a thread (read-only), at most once per `searchInterval` when the last search found none;
    /// found, the account turns `on` (ADR 0013 §7). `declined`, `off` and an unreadable state do nothing.
    func start() async {
        guard !started else { return }
        started = true
        // Only this start's own failure counts: a network failure left by an earlier call (Réglages) must not re-arm it.
        lastFailureWasNetwork = false
        defer { if case .failed = status, lastFailureWasNetwork { started = false } }
        guard let copy = await loadCopy() else { return }
        guard await isLoggedIn() else { return }
        switch record?.state {
        case .on?:
            await run { [self] () async throws(MPStorageSyncError) in try await syncOnce() }
        case .unasked?:
            if let last = copy.lastSearch, clock().timeIntervalSince(last) < Self.searchInterval { return }
            await run { [self] () async throws(MPStorageSyncError) in
                if try await sync.detect(now: clock()) == .found { decide(.on) }
            }
        case .declined?, .off?, nil:
            break
        }
    }

    /// The Réglages toggle. Off: `off`, nothing deleted on the forum or the device. On: the account's thread (cached, else
    /// searched) is read and the account turns `on`; with none, the creation question is asked (`asksCreation`).
    func setEnabled(_ enabled: Bool) async {
        guard enabled else {
            decide(.off)
            return
        }
        guard await isLoggedIn() else {
            status = .failed("Connectez-vous pour activer le stockage MP.")
            return
        }
        await run { [self] () async throws(MPStorageSyncError) in
            guard try await sync.detect(now: clock()) == .found else {
                asksCreation = true
                return
            }
            decide(.on)
            threadMissing = false
            // Edits made before (another session of this account) are written now.
            try await syncOnce()
        }
    }

    /// The answer to the creation question: yes creates the thread (LOT-052 searches first, so never a second one) and
    /// turns the account `on`; no records `declined` for this account only.
    func answerCreation(_ create: Bool) async {
        asksCreation = false
        guard create else {
            decide(.declined)
            return
        }
        await run { [self] () async throws(MPStorageSyncError) in
            try await sync.create(now: clock())
            decide(.on)
            threadMissing = false
        }
    }

    /// "Resynchroniser": reads the forum copy and writes the local edits (only while `on`).
    func resync() async {
        guard isOn else { return }
        await run { [self] () async throws(MPStorageSyncError) in try await syncOnce() }
    }

    /// Whether `function` is on for the account (#859): every function is on by default; an unreadable record turns all off.
    func isEnabled(_ function: MPStorageFunction) -> Bool { record?.isEnabled(function) ?? false }

    /// The functions whose switch Réglages shows: those whose lot has shipped (no dead switch, #859). Blacklist (LOT-131)
    /// and bookmarks (LOT-132) join when their lots merge.
    static let shippedFunctions: [MPStorageFunction] = [.mpFlags]

    /// A function switch of Réglages. Never deletes the section on the forum nor any other client's data: the app only
    /// stops reading and writing that section (#859). An edit queued before the switch-off is still written at the
    /// next sync.
    func setFunction(_ function: MPStorageFunction, enabled: Bool) {
        guard states.setFunction(function, enabled: enabled, for: account) else { return }
        record = states.record(for: account)
    }

    /// What a first write of `function` (bookmark, blacklist entry) does for this account (ADR 0013 §7): a function
    /// switched off stays on the device.
    func writeConsent(for function: MPStorageFunction) -> WriteConsent {
        guard isEnabled(function) else { return .deviceOnly }
        switch record?.state {
        case .on?: return .sync
        case .unasked?: return .ask
        case .declined?, .off?, nil: return .deviceOnly
        }
    }

    /// Applies a LOT-062 edit of `function`'s section locally, then writes it (LOT-131, LOT-132). Only while `on` and the
    /// function is on; returns whether it changed the document. A failed write keeps the edit for the next sync.
    @discardableResult
    func edit(
        _ function: MPStorageFunction, _ change: @escaping @Sendable (inout MPStorageDocument, MPStorageStamp) throws -> Bool
    ) async -> Bool {
        guard isOn, isEnabled(function) else { return false }
        var changed = false
        await run { [self] () async throws(MPStorageSyncError) in
            changed = try await sync.edit(now: clock(), change)
            if changed { try await syncOnce() }
        }
        return changed
    }

    /// The document for `function`'s reader (LOT-131, LOT-132): nil unless the account is `on` and the function is on.
    func document(for function: MPStorageFunction) -> MPStorageDocument? {
        isOn && isEnabled(function) ? document : nil
    }

    /// The stored read position of a group conversation (`MPListView.swift:354-373` @ 87fe0d1c), only while `on` and the
    /// "dark topic" function is on; nil for a one-to-one conversation and for a flag
    /// without a page above 0 (legacy's link would hold `(null)`).
    func flag(for thread: PrivateMessageThread) -> MPStorageMPFlag? {
        guard isOn, isEnabled(.mpFlags), thread.isGroup, let document, let post = thread.summary.topicID?.topic,
              let flag = MPStorageSync.flag(forThread: post, in: document), let page = flag.page, page > 0
        else { return nil }
        return flag
    }

    // MARK: Internals

    private func syncOnce() async throws(MPStorageSyncError) {
        threadMissing = try await sync.sync(now: clock()) == .noThread
    }

    private func decide(_ state: MPStorageSyncState) {
        states.set(state, for: account, at: clock())
        record = states.record(for: account)
    }

    /// Runs one call: `working` while it runs, then the copy is shown again and the status says how it went.
    private func run(_ work: () async throws(MPStorageSyncError) -> Void) async {
        status = .working
        lastFailureWasNetwork = false
        do {
            try await work()
            status = threadMissing ? .failed("Le MP de stockage est introuvable.") : .idle
        } catch {
            status = .failed(Self.message(for: error))
            if case .transport(.network) = error { lastFailureWasNetwork = true }
        }
        _ = await loadCopy()
    }

    /// Shows the device copy: last sync and document. A copy that cannot be read is said, and nil returned.
    private func loadCopy() async -> MPStorageSyncCopy? {
        do {
            let copy = try await sync.copy()
            lastSync = copy.lastSync
            document = try? copy.currentText.map(MPStorageCodec.decode)
            return copy
        } catch {
            status = .failed(Self.message(for: error))
            return nil
        }
    }

    /// The French message of a failure; never document text or pseudos.
    static func message(for error: MPStorageSyncError) -> String {
        switch error {
        case .storage, .unreadableCopy:
            "La copie locale du stockage MP est illisible."
        case .notLoaded:
            "Le stockage MP n'a pas encore été lu."
        case .document, .transport(.document):
            "Le stockage MP ne peut pas être écrit : caractère non pris en charge ou taille maximale atteinte."
        case .transport(let failure):
            message(for: failure)
        }
    }

    private static func message(for failure: MPStorageTransportError) -> String {
        switch failure {
        case .network:
            "Réseau indisponible : la synchronisation reprendra plus tard."
        case .searchLimitReached(let pages):
            "Le MP de stockage n'a pas été trouvé dans les \(pages) premières pages de MP."
        case .invalidDocument:
            "Le document du stockage MP sur le forum est illisible."
        case .posting(.unconfirmed), .notVerified:
            "Écriture non confirmée : elle sera vérifiée à la prochaine synchronisation."
        case .posting(.notLoggedIn), .list(.notAuthenticated):
            "Connectez-vous pour synchroniser le stockage MP."
        default:
            "La synchronisation du stockage MP a échoué."
        }
    }
}
