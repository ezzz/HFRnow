import Foundation
import HFRClient
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// The pure merge of LOT-131: what a sync does to each side.
struct BlocklistSyncPlanTests {
    static func document(_ names: [String], tombstones: [String] = []) throws -> MPStorageDocument {
        try MPStorageCodec.decode(blocklistDocumentText(names, tombstones: tombstones))
    }

    @Test func anEmptyRemoteListNeverEmptiesTheLocalOne() throws {
        let plan = BlocklistSyncPlan.make(
            local: ["Alpha", "Beta"], before: try Self.document(["Alpha", "Beta"]), after: try Self.document([]), held: []
        )
        #expect(plan.removeLocally.isEmpty)
        #expect(plan.addRemotely == ["Alpha", "Beta"])
    }

    @Test func aRemoteRemovalIsTakenWhileTheListStillHoldsEntries() throws {
        let plan = BlocklistSyncPlan.make(
            local: ["Alpha", "Beta"], before: try Self.document(["Alpha", "Beta"]), after: try Self.document(["Beta"]), held: []
        )
        #expect(plan.removeLocally == ["Alpha"])
        #expect(plan.addRemotely.isEmpty)
    }

    @Test func theLastEntryRemovedWithATombstoneIsTaken() throws {
        let plan = BlocklistSyncPlan.make(
            local: ["Alpha"], before: try Self.document(["Alpha"]), after: try Self.document([], tombstones: ["alpha"]), held: []
        )
        #expect(plan.removeLocally == ["Alpha"])
        #expect(plan.addRemotely.isEmpty)
    }

    @Test func theFirstReadRemovesNothingAndUnitesBothLists() throws {
        let plan = BlocklistSyncPlan.make(local: ["Alpha"], before: nil, after: try Self.document(["Gamma"]), held: [])
        #expect(plan == BlocklistSyncPlan(addLocally: ["Gamma"], addRemotely: ["Alpha"]))
    }

    @Test func pseudosMatchByTheSharedRuleWhateverTheCaseOrFormatCharacters() throws {
        let plan = BlocklistSyncPlan.make(local: ["Alpha"], before: nil, after: try Self.document(["aLPHA\u{200B}"]), held: [])
        #expect(plan.isEmpty)
    }

    @Test func aRemovalTheDocumentLacksIsWrittenAndNeverImportedBack() throws {
        let plan = BlocklistSyncPlan.make(
            local: [], before: nil, after: try Self.document(["ALPHA", "Beta"]),
            held: [BlocklistChange(pseudo: "Alpha", added: false)]
        )
        #expect(plan.addLocally == ["Beta"])
        #expect(plan.removeRemotely == ["ALPHA"])
    }

    @Test func aLocalAdditionWinsOverARemoteRemovalOfTheSamePseudo() throws {
        let plan = BlocklistSyncPlan.make(
            local: ["Alpha", "Beta"], before: try Self.document(["Alpha", "Beta"]), after: try Self.document(["Beta"]),
            held: [BlocklistChange(pseudo: "Alpha", added: true)]
        )
        #expect(plan.removeLocally.isEmpty)
        #expect(plan.addRemotely == ["Alpha"])
    }

    @Test func aPseudoTheForumCannotStoreStaysOnTheDeviceAndTheOthersAreWritten() throws {
        var document = try Self.document([])
        let changed = try BlocklistSyncPlan.apply(
            adding: ["Alpha", "Smile\u{1F600}", "Beta"], removing: [], to: &document,
            stamp: MPStorageStamp(date: Date(timeIntervalSince1970: 1_800_000_000))
        )
        #expect(changed)
        #expect(BlocklistSyncPlan.usernames(in: document) == ["Alpha", "Beta"])
    }
}

/// The blocklist kept in step with the account's MPStorage document (LOT-131), over a scripted forum (no session exists).
@MainActor
struct BlocklistSyncModelTests {
    struct Fixture {
        let sync: BlocklistSyncModel
        let base: MPStorageSyncModelTests.Fixture
        let store: PseudoListStore
        let manager: PseudoListManager
        let changes: BlocklistChangeLog
        let held: HeldBlocklistChanges

        var remote: FakeMPStorageRemote { base.remote }

        func local() async -> [String] {
            await store.blocklist(for: MPStorageSyncModelTests.account).map(\.pseudo)
        }
    }

    static func make(
        thread: Int?, state: MPStorageSyncState? = nil, copy: MPStorageCopy = MPStorageCopy(),
        remote: [String] = [], local: [String] = []
    ) async throws -> Fixture {
        let base = try await MPStorageSyncModelTests.make(
            thread: thread, state: state, copy: copy, text: blocklistDocumentText(remote)
        )
        await base.remote.mergeOnSave()
        let store = PseudoListStore(persistence: InMemoryPseudoListPersistence())
        for pseudo in local { try await store.block(pseudo, account: MPStorageSyncModelTests.account) }
        let held = HeldBlocklistChanges()
        let changes = BlocklistChangeLog(held: held)
        let sync = BlocklistSyncModel(mpStorage: base.model, store: store, changes: changes, refreshLists: {})
        let manager = PseudoListManager(store: store, account: MPStorageSyncModelTests.account, blocklistChanges: changes)
        return Fixture(sync: sync, base: base, store: store, manager: manager, changes: changes, held: held)
    }

    /// The copy of an account that synced `names` before.
    static func syncedCopy(_ names: [String]) -> MPStorageCopy {
        MPStorageCopy(post: 7, base: blocklistDocumentText(names))
    }

    @Test func aStartMergesBothListsInsteadOfReplacingTheLocalOne() async throws {
        let fixture = try await Self.make(
            thread: 7, state: .on, copy: Self.syncedCopy([]), remote: ["Gamma"], local: ["Alpha"]
        )
        await fixture.base.model.start()
        #expect(Set(await fixture.local()) == ["Alpha", "Gamma"])
        #expect(Set(try await fixture.remote.blocklist()) == ["Alpha", "Gamma"])
    }

    @Test func anEmptyRemoteListNeverEmptiesTheLocalOne() async throws {
        let fixture = try await Self.make(
            thread: 7, state: .on, copy: Self.syncedCopy(["Alpha", "Beta"]), remote: [], local: ["Alpha", "Beta"]
        )
        await fixture.base.model.start()
        #expect(await fixture.local() == ["Alpha", "Beta"])
        #expect(Set(try await fixture.remote.blocklist()) == ["Alpha", "Beta"])
    }

    @Test func aRemovalMadeOnAnotherClientIsTaken() async throws {
        let fixture = try await Self.make(
            thread: 7, state: .on, copy: Self.syncedCopy(["Alpha", "Beta"]), remote: ["Beta"], local: ["Alpha", "Beta"]
        )
        await fixture.base.model.start()
        #expect(await fixture.local() == ["Beta"])
        #expect(try await fixture.remote.blocklist() == ["Beta"])
    }

    @Test func aLocalAdditionIsWrittenToTheDocumentWhileOn() async throws {
        let fixture = try await Self.make(thread: 7, state: .on, copy: Self.syncedCopy([]))
        await fixture.base.model.start()
        try await fixture.manager.add("Alpha", to: .blocklist)
        #expect(fixture.changes.pending == [BlocklistChange(pseudo: "Alpha", added: true)])
        await fixture.sync.handle(BlocklistChange(pseudo: "Alpha", added: true))
        #expect(try await fixture.remote.blocklist() == ["Alpha"])
        #expect(fixture.changes.pending.isEmpty)
    }

    @Test func aLocalRemovalRemovesEveryVariantFromTheDocument() async throws {
        let variants = ["ALPHA", "Alpha\u{200B}", "Beta"]
        let fixture = try await Self.make(
            thread: 7, state: .on, copy: Self.syncedCopy(variants), remote: variants, local: ["Alpha", "Beta"]
        )
        await fixture.base.model.start()
        try await fixture.manager.remove("Alpha", from: .blocklist)
        await fixture.sync.handle(BlocklistChange(pseudo: "Alpha", added: false))
        #expect(try await fixture.remote.blocklist() == ["Beta"])
        #expect(await fixture.local() == ["Beta"])
        // One write for every variant, not one per variant left to the next merge.
        #expect(await fixture.remote.calls.filter { $0 == .save }.count == 1)
    }

    @Test func aRemovalNotYetWrittenIsNotImportedBackByASync() async throws {
        let fixture = try await Self.make(
            thread: 7, state: .on, copy: Self.syncedCopy(["Alpha"]), remote: ["Alpha"], local: ["Alpha"]
        )
        // The removal is on the device; the consumer has not taken it yet when a sync runs.
        try await fixture.manager.remove("Alpha", from: .blocklist)
        await fixture.base.model.start()
        #expect(await fixture.local().isEmpty)
        #expect(try await fixture.remote.blocklist().isEmpty)
    }

    @Test func aWriteBeforeAnyStartMergesFromTheStoredCopy() async throws {
        // Another client removed Alpha; the reader blocks Gamma before the Messages tab or Réglages ever started the sync.
        let fixture = try await Self.make(
            thread: 7, state: .on, copy: Self.syncedCopy(["Alpha", "Beta"]), remote: ["Beta"], local: ["Alpha", "Beta"]
        )
        try await fixture.manager.add("Gamma", to: .blocklist)
        await fixture.sync.handle(BlocklistChange(pseudo: "Gamma", added: true))
        #expect(Set(await fixture.local()) == ["Beta", "Gamma"])
        #expect(Set(try await fixture.remote.blocklist()) == ["Beta", "Gamma"])
    }

    @Test func anUnblockThenReblockLeavesThePseudoBlockedOnBothSides() async throws {
        let fixture = try await Self.make(
            thread: 7, state: .on, copy: Self.syncedCopy(["Alpha", "Beta"]), remote: ["Alpha", "Beta"], local: ["Alpha", "Beta"]
        )
        await fixture.base.model.start()
        try await fixture.manager.remove("Alpha", from: .blocklist)
        try await fixture.manager.add("Alpha", to: .blocklist)
        await fixture.sync.handle(BlocklistChange(pseudo: "Alpha", added: false))
        await fixture.sync.handle(BlocklistChange(pseudo: "Alpha", added: true))
        #expect(Set(try await fixture.remote.blocklist()) == ["Alpha", "Beta"])
        #expect(Set(await fixture.local()) == ["Alpha", "Beta"])
        #expect(fixture.changes.pending.isEmpty)
    }

    @Test func aMissingThreadMergesNothingFromTheStoredCopy() async throws {
        let fixture = try await Self.make(thread: nil, state: .on, copy: Self.syncedCopy(["Gamma"]), local: ["Alpha"])
        await fixture.base.model.start()
        #expect(fixture.base.model.threadMissing)
        #expect(await fixture.local() == ["Alpha"])
    }

    @Test func anEditThatChangesNothingStartsNoMerge() async throws {
        // Else a pseudo the forum cannot store (skipped by every merge write) would merge and write again forever.
        let fixture = try await Self.make(thread: 7, state: .on, copy: Self.syncedCopy([]))
        await fixture.base.model.start()
        var merges = 0
        fixture.base.model.afterSync = { _, _ in merges += 1 }
        await fixture.base.model.edit(.ignoreList) { _, _ in false }
        #expect(merges == 0)
        await fixture.base.model.resync()
        #expect(merges == 1)
    }

    @Test func aNoOpEditDuringASyncKeepsThatSyncsMerge() async throws {
        // Another client removed Alpha and added Gamma; the device unblocks Delta, which the document never listed, while the
        // start's read is in flight: that edit changes nothing, and must not cancel the start's merge.
        let account = MPStorageSyncModelTests.account
        let fake = FakeMPStorageRemote(thread: 7, text: blocklistDocumentText(["Beta", "Gamma"]))
        await fake.mergeOnSave()
        let gate = ReadGate()
        let states = MPStorageSyncStateStore(settings: InMemorySettingsStore())
        states.set(.on, for: account, at: MPStorageSyncModelTests.now.addingTimeInterval(-60))
        let copies = MPStorageCopyStore(persistence: InMemorySmallStorePersistence<MPStorageCopyDocument>())
        try await copies.save(Self.syncedCopy(["Alpha", "Beta"]), for: account)
        let model = MPStorageSyncModel(
            account: account,
            sync: MPStorageSync(
                remote: GatedMPStorageRemote(inner: fake, gate: gate),
                persistence: MPStorageCopyPersistence(store: copies, account: account)
            ),
            states: states, isLoggedIn: { true }, clock: { MPStorageSyncModelTests.now }
        )
        let store = PseudoListStore(persistence: InMemoryPseudoListPersistence())
        for pseudo in ["Alpha", "Beta", "Delta"] { try await store.block(pseudo, account: account) }
        let changes = BlocklistChangeLog()
        let sync = BlocklistSyncModel(mpStorage: model, store: store, changes: changes, refreshLists: {})
        let manager = PseudoListManager(store: store, account: account, blocklistChanges: changes)

        let starting = Task { await model.start() }
        while await gate.waiting == 0 { try await Task.sleep(for: .milliseconds(5)) }
        try await manager.remove("Delta", from: .blocklist)
        let handling = Task { await sync.handle(BlocklistChange(pseudo: "Delta", added: false)) }
        // Lets the edit queue behind the read before the read answers.
        try await Task.sleep(for: .milliseconds(50))
        await gate.release()
        await starting.value
        await handling.value
        #expect(Set(await store.blocklist(for: account).map(\.pseudo)) == ["Beta", "Gamma"])
        #expect(Set(try await fake.blocklist()) == ["Beta", "Gamma"])
    }

    @Test func aRemovalHeldInAnotherWindowIsNotImportedBack() async throws {
        // LOT-146: each window has its own log and model over the account's one store; the held changes are the account's.
        let fixture = try await Self.make(
            thread: 7, state: .on, copy: Self.syncedCopy(["Alpha"]), remote: ["Alpha"], local: ["Alpha"]
        )
        let otherWindow = PseudoListManager(
            store: fixture.store, account: MPStorageSyncModelTests.account, blocklistChanges: BlocklistChangeLog(held: fixture.held)
        )
        try await otherWindow.remove("Alpha", from: .blocklist)
        await fixture.base.model.start()
        #expect(await fixture.local().isEmpty)
        #expect(try await fixture.remote.blocklist().isEmpty)
    }

    @Test func everyWindowOfAnAccountSharesItsHeldChanges() {
        #expect(HeldBlocklistChanges.shared(for: "Window\u{200B}Test") === HeldBlocklistChanges.shared(for: "windowtest"))
        #expect(HeldBlocklistChanges.shared(for: "WindowTest") !== HeldBlocklistChanges.shared(for: "OtherWindowTest"))
    }

    @Test func aFirstWriteOfAnAccountThatNeverChoseAsksAndSendsNothing() async throws {
        let fixture = try await Self.make(thread: 7, state: .unasked)
        try await fixture.manager.add("Alpha", to: .blocklist)
        await fixture.sync.handle(BlocklistChange(pseudo: "Alpha", added: true))
        #expect(fixture.sync.asksConsent)
        #expect(await fixture.remote.calls.isEmpty)
        #expect(fixture.base.model.record?.state == .unasked)
    }

    @Test func yesWithAThreadSwitchesOnAndWritesTheDeviceList() async throws {
        let fixture = try await Self.make(thread: 7, state: .unasked, remote: ["Gamma"], local: ["Beta"])
        try await fixture.manager.add("Alpha", to: .blocklist)
        await fixture.sync.handle(BlocklistChange(pseudo: "Alpha", added: true))
        await fixture.sync.answerConsent(true)
        #expect(fixture.base.model.isOn)
        #expect(Set(try await fixture.remote.blocklist()) == ["Alpha", "Beta", "Gamma"])
        #expect(Set(await fixture.local()) == ["Alpha", "Beta", "Gamma"])
        #expect(fixture.changes.pending.isEmpty)
    }

    @Test func yesWithoutAThreadAsksTheCreationQuestionFromTheWrite() async throws {
        let fixture = try await Self.make(thread: nil, state: .unasked)
        await fixture.sync.answerConsent(true)
        #expect(fixture.base.model.asksCreation)
        #expect(fixture.base.model.creationPrompt == .write)
        #expect(await fixture.remote.calls == [.find])
        await fixture.base.model.answerCreation(true)
        #expect(fixture.base.model.isOn)
    }

    @Test func noKeepsTheListOnTheDeviceForThisAccount() async throws {
        let fixture = try await Self.make(thread: 7, state: .unasked)
        try await fixture.manager.add("Alpha", to: .blocklist)
        await fixture.sync.handle(BlocklistChange(pseudo: "Alpha", added: true))
        await fixture.sync.answerConsent(false)
        #expect(fixture.base.model.record?.state == .declined)
        #expect(await fixture.remote.calls.isEmpty)
        #expect(fixture.changes.pending.isEmpty)
        #expect(await fixture.local() == ["Alpha"])
    }

    @Test(arguments: [MPStorageSyncState.declined, .off])
    func aDecidedAccountKeepsItsWritesOnTheDevice(_ state: MPStorageSyncState) async throws {
        let fixture = try await Self.make(thread: 7, state: state)
        try await fixture.manager.add("Alpha", to: .blocklist)
        await fixture.sync.handle(BlocklistChange(pseudo: "Alpha", added: true))
        #expect(!fixture.sync.asksConsent)
        #expect(await fixture.remote.calls.isEmpty)
        #expect(fixture.changes.pending.isEmpty)
    }

    @Test func theBlocklistFunctionOffNeitherReadsNorWritesTheSection() async throws {
        let fixture = try await Self.make(
            thread: 7, state: .on, copy: Self.syncedCopy([]), remote: ["Gamma"], local: ["Alpha"]
        )
        fixture.base.model.setFunction(.ignoreList, enabled: false)
        await fixture.base.model.start()
        #expect(await fixture.local() == ["Alpha"])
        #expect(try await fixture.remote.blocklist() == ["Gamma"])
    }
}
