import Foundation
import HFRModels

/// Copies the allowlist, the super-favourites, the app smiley favourites and the reading positions to the iCloud
/// key-value store and back (LOT-172 part 2, ADR 0013 §3 and Amendment 2). The local stores stay the masters on the
/// device; each list is one cloud key holding the whole list (`SyncedListEnvelope`), last writer wins on the whole list,
/// and the reading positions are merged per topic, newest first.
///
/// Every event (a cloud change, a saved local change, the account list, a timer) is handled one at a time by `run()`,
/// so a push never interleaves with an apply. Apple ID rules (Amendment 2): nothing is applied or pushed while no Apple ID
/// is signed in, and the lists stay; when a different Apple ID signs in, the lists of the previous one are set aside on
/// the device (`SyncedListsDeviceState`), never uploaded under the new one, and come back if it signs in again within
/// `SyncedSettingsStore.quarantineLifetime`.
public actor SyncedListsStore {
    /// The number of reading positions per account kept in the cloud (the most recently updated).
    public static let positionsLimit = 200
    /// Apple's limit on the length of a key, in UTF-8 bytes.
    public static let maximumKeyLength = 64
    /// The cloud key of the allowlist.
    static let allowlistKey = "allowlist"

    enum Event: Sendable {
        case cloud(SyncedStoreChange)
        case listsChanged
        case positionsChanged
        case positionsDue(Int)
        case flushPositions
        case accountsChanged
        case graceEnded
    }

    /// The local stores, by the prefix of their cloud keys.
    enum Slot: String, CaseIterable {
        case allowlist
        case superFavorites = "superfavorites"
        case smileyFavorites = "smileyfavorites"
        case positions
    }

    let cloud: any SyncedKeyValueStore
    let pseudoLists: PseudoListStore
    let superFavorites: SuperFavoritesStore
    let smileyFavorites: AppSmileyFavoritesStore
    let positions: ReadingPositionStore
    let accounts: @Sendable () async -> [String]
    let clock: @Sendable () -> Date
    let sleep: @Sendable (Duration) async -> Void
    let positionsDelay: Duration
    let launchGrace: Duration
    let events: AsyncStream<Event>
    let sink: AsyncStream<Event>.Continuation

    var device: SmallStoreState<SyncedListsDeviceState>
    var deviceStateLoaded = false
    var owner: String?
    var stale: [String: String] = [:]
    var unsaved: [String: SyncQuarantineEntry] = [:]
    /// Per cloud key, the digest of the list last synced (`SyncedListsDeviceState.synced`).
    var synced: [String: String] = [:]
    /// Whether the device file lags behind the owner, the stale stores or the digests: the sync then pauses, since
    /// the next launch would read an older owner.
    var stateUnsaved = false
    var positionsTimer: Task<Void, Never>?
    var positionsPending = false
    var positionsGeneration = 0
    var waitingForStore = false

    /// The cloud keys the store refused for quota; their local lists are kept.
    public internal(set) var quotaViolations: Set<String> = []
    /// Accounts whose cloud keys would exceed `maximumKeyLength`: their lists stay on the device.
    public internal(set) var unsyncedAccounts: Set<String> = []
    /// Why the device state file could not be read or written, or nil. Unreadable, it stops the sync: the owner of the
    /// local lists is unknown, so nothing may be pushed.
    public internal(set) var deviceStateFailure: SmallStoreError?

    /// Creates the sync over the cloud store, the four local stores, the app's accounts (`md_user` as the app stores
    /// it) and the device-only state file. Nothing happens until `run()`.
    public init(
        cloud: any SyncedKeyValueStore,
        pseudoLists: PseudoListStore,
        superFavorites: SuperFavoritesStore,
        smileyFavorites: AppSmileyFavoritesStore,
        positions: ReadingPositionStore,
        deviceState: any SmallStorePersistence<SyncedListsDeviceState>,
        accounts: @escaping @Sendable () async -> [String],
        clock: @escaping @Sendable () -> Date = { Date() },
        positionsDelay: Duration = .seconds(30),
        launchGrace: Duration = .seconds(5),
        sleep: @escaping @Sendable (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.cloud = cloud
        self.pseudoLists = pseudoLists
        self.superFavorites = superFavorites
        self.smileyFavorites = smileyFavorites
        self.positions = positions
        self.accounts = accounts
        self.clock = clock
        self.positionsDelay = positionsDelay
        self.launchGrace = launchGrace
        self.sleep = sleep
        device = SmallStoreState(persistence: deviceState)
        (events, sink) = AsyncStream.makeStream(of: Event.self)
    }

    // MARK: Running

    /// Handles an Apple ID change made while the app was not running, then every event until the task is cancelled.
    /// Call it once.
    public func run() async {
        await start()
        let cloudChanges = cloud.changes()
        let allowlistChanges = await pseudoLists.allowlistChanges()
        let superFavoriteChanges = await superFavorites.changes()
        let smileyFavoriteChanges = await smileyFavorites.changes()
        let positionChanges = await positions.changes()
        await withTaskGroup(of: Void.self) { group in
            let sink = sink
            group.addTask { for await change in cloudChanges { sink.yield(.cloud(change)) } }
            group.addTask { for await _ in allowlistChanges { sink.yield(.listsChanged) } }
            group.addTask { for await _ in superFavoriteChanges { sink.yield(.listsChanged) } }
            group.addTask { for await _ in smileyFavoriteChanges { sink.yield(.listsChanged) } }
            group.addTask { for await _ in positionChanges { sink.yield(.positionsChanged) } }
            for await event in events {
                await handle(event)
            }
            positionsTimer?.cancel()
            group.cancelAll()
        }
    }

    /// Queues the push of a pending reading-position change, handled before any later event; the app calls it when it
    /// goes to the background (the system uploads from its own queue afterwards).
    nonisolated public func flushPositions() {
        sink.yield(.flushPositions)
    }

    /// Tells the sync the app's accounts changed: an added account gets the initial-sync rule.
    nonisolated public func accountsDidChange() {
        sink.yield(.accountsChanged)
    }

    /// The launch: the device file is read, an Apple ID change made meanwhile is handled, then the initial-sync rule.
    func start() async {
        guard let document = device.document() else {
            deviceStateFailure = device.failure()
            return
        }
        deviceStateLoaded = true
        owner = document.owner
        stale = document.stale
        synced = document.synced
        purge()
        await settleStaleStores()
        guard let current = cloud.accountIdentity() else { return }
        guard let owner else {
            // No owner yet: the lists made without an Apple ID seed this one (ADR 0013 §5 step 2).
            setOwner(current)
            await reconcile()
            return
        }
        if cloud.isCurrentAccount(owner) {
            await reconcile()
            return
        }
        await switchOwner(from: owner, to: current)
        // The token can name the new Apple ID before the system replaced the store's content: wait for the store.
        waitingForStore = true
        schedule(.graceEnded, after: launchGrace)
    }

    /// Handles one event (see the type's rules).
    func handle(_ event: Event) async {
        guard deviceStateLoaded else { return }
        if stateUnsaved { saveDeviceState() }
        await settleStaleStores()
        switch event {
        case .cloud(let change):
            await handle(change)
        case .listsChanged:
            await pushLists()
        case .positionsChanged:
            positionsPending = true
            positionsGeneration += 1
            positionsTimer?.cancel()
            positionsTimer = schedule(.positionsDue(positionsGeneration), after: positionsDelay)
        case .positionsDue(let generation):
            if generation == positionsGeneration { await pushPendingPositions() }
        case .flushPositions:
            positionsGeneration += 1
            positionsTimer?.cancel()
            await pushPendingPositions()
        case .accountsChanged:
            await reconcile()
        case .graceEnded:
            await endGrace()
        }
    }

    private func pushPendingPositions() async {
        guard positionsPending else { return }
        await pushAllPositions()
    }

    private func endGrace() async {
        guard waitingForStore else { return }
        waitingForStore = false
        await reconcile()
    }

    func handle(_ change: SyncedStoreChange) async {
        let wasWaiting = waitingForStore
        waitingForStore = false
        if change.reason != .accountChange, cloud.accountIdentity() != nil,
           owner.map({ !cloud.isCurrentAccount($0) }) ?? true {
            // An Apple ID change whose notification was missed.
            if change.reason == .quotaViolation { quotaViolations.formUnion(change.keys.filter(Self.isListKey)) }
            await accountChanged()
            return
        }
        switch change.reason {
        case .accountChange:
            await accountChanged()
        case .initialSync:
            await reconcile()
        case .quotaViolation:
            quotaViolations.formUnion(change.keys.filter(Self.isListKey))
            if wasWaiting { await reconcile() }
        case .serverChange:
            if wasWaiting {
                await reconcile()
            } else {
                for key in change.keys where Self.isListKey(key) { await apply(key) }
            }
        }
    }

    // MARK: Apple ID

    /// Whether lists may be applied and pushed: an Apple ID signed in that owns the local lists, its store content
    /// trusted, a format this build reads.
    var isActive: Bool {
        guard deviceStateLoaded, !stateUnsaved, !waitingForStore, let owner, cloud.accountIdentity() != nil,
              cloud.isCurrentAccount(owner) else { return false }
        return cloudSchemaIsReadable
    }

    func accountChanged() async {
        // Signed out: the lists stay and nothing is pushed until an Apple ID signs in (Amendment 2).
        guard let current = cloud.accountIdentity() else { return }
        if let owner, !cloud.isCurrentAccount(owner) {
            await switchOwner(from: owner, to: current)
        } else if owner == nil {
            setOwner(current)
        }
        await reconcile()
    }

    /// Sets the previous Apple ID's lists aside, makes the new one the owner, then brings back its lists, once the
    /// device file names it: restored lists must never be set aside under the previous Apple ID at the next launch.
    func switchOwner(from previous: String, to current: String) async {
        await setAside(owner: previous)
        synced = [:]
        setOwner(current)
        guard !stateUnsaved else { return }
        await restore(for: current)
    }

    func setOwner(_ identity: String) {
        owner = identity
        saveDeviceState()
    }

    // MARK: Keys

    /// The cloud key of an account's list, nil when the account key is empty, or when the account's longest key
    /// would exceed `maximumKeyLength`: an account syncs all its lists or none.
    func cloudKey(_ slot: Slot, account: String) -> String? {
        let accountKey = AccountKey.make(account)
        guard !accountKey.isEmpty else { return nil }
        let longest = Slot.allCases.map { $0.rawValue.utf8.count }.max() ?? 0
        guard longest + 1 + accountKey.utf8.count <= Self.maximumKeyLength else {
            unsyncedAccounts.insert(account)
            return nil
        }
        return "\(slot.rawValue).\(accountKey)"
    }

    func slot(of key: String) -> Slot {
        Slot(rawValue: String(key.prefix { $0 != "." })) ?? .allowlist
    }

    static func isPositionsKey(_ key: String) -> Bool {
        key.hasPrefix("\(Slot.positions.rawValue).")
    }

    static func isListKey(_ key: String) -> Bool {
        key == allowlistKey || Slot.allCases.contains { $0 != .allowlist && key.hasPrefix("\($0.rawValue).") }
    }

    var cloudSchemaIsReadable: Bool {
        guard case .int(let version)? = cloud.value(forKey: SyncedSettingsStore.schemaVersionKey) else { return true }
        return version <= SyncedSettingsStore.schemaVersion
    }

    /// Topics and places of positions, dates left out.
    static func places(_ records: [ReadingPositionRecord]) -> Set<ReadingPositionRecord> {
        Set(records.map { record in
            var record = record
            record.position.updatedAt = .distantPast
            return record
        })
    }

    @discardableResult
    func schedule(_ event: Event, after delay: Duration) -> Task<Void, Never> {
        let sink = sink
        let sleep = sleep
        return Task {
            await sleep(delay)
            guard !Task.isCancelled else { return }
            sink.yield(event)
        }
    }
}
