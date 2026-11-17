import Foundation
import HFRClient
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

extension FakeMPStorageRemote {
    /// Another client wrote the document.
    func replaceText(_ newText: String) { text = newText }

    /// The usernames of the forum document as it stands.
    func blocklist() throws -> [String] {
        BlocklistSyncPlan.usernames(in: try MPStorageCodec.decode(text))
    }
}

/// A `0.1` document whose blocklist holds `names` (and `tombstones`, ids as written).
func blocklistDocumentText(_ names: [String], tombstones: [String] = []) -> String {
    let list = names.map { #"{"createDate":1700000000000,"username":"\#($0)"}"# }.joined(separator: ",")
    let dead = tombstones.map { #"{"deleteDate":1790000000000,"id":"\#($0)"}"# }.joined(separator: ",")
    let tombstoneKey = tombstones.isEmpty ? "" : #","tombstones":[\#(dead)]"#
    return #"{"data":[{"blacklist":{"list":[\#(list)]\#(tombstoneKey)},"bookmarks":{"list":[]},"mpFlags":{"list":[]},"version":"0.1"}]}"#
}

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

        var remote: FakeMPStorageRemote { base.remote }

        func local() async -> [String] {
            await store.blocklist(for: MPStorageSyncModelTests.account).map(\.pseudo)
        }
    }

    static func make(
        thread: Int?, state: MPStorageSyncState? = nil, copy: MPStorageCopy = MPStorageCopy(),
        remote: [String] = [], local: [String] = [], storePersistence: (any PseudoListPersistence)? = nil
    ) async throws -> Fixture {
        let base = try await MPStorageSyncModelTests.make(
            thread: thread, state: state, copy: copy, text: blocklistDocumentText(remote)
        )
        let store = PseudoListStore(persistence: storePersistence ?? InMemoryPseudoListPersistence())
        for pseudo in local { try await store.block(pseudo, account: MPStorageSyncModelTests.account) }
        let changes = BlocklistChangeLog()
        let sync = BlocklistSyncModel(mpStorage: base.model, store: store, changes: changes, refreshLists: {})
        let manager = PseudoListManager(store: store, account: MPStorageSyncModelTests.account, blocklistChanges: changes)
        return Fixture(sync: sync, base: base, store: store, manager: manager, changes: changes)
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

    @Test func aLocalRemovalRemovesEveryCaseVariantFromTheDocument() async throws {
        let fixture = try await Self.make(
            thread: 7, state: .on, copy: Self.syncedCopy(["ALPHA", "Beta"]), remote: ["ALPHA", "Beta"], local: ["Alpha", "Beta"]
        )
        await fixture.base.model.start()
        try await fixture.manager.remove("Alpha", from: .blocklist)
        await fixture.sync.handle(BlocklistChange(pseudo: "Alpha", added: false))
        #expect(try await fixture.remote.blocklist() == ["Beta"])
        #expect(await fixture.local() == ["Beta"])
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
