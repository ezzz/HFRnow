import Foundation
import HFRClient
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// A forum side answering from scripts (no session exists here: nothing can reach the forum), recording its calls.
actor FakeMPStorageRemote: MPStorageRemote {
    enum Call: Equatable { case find, read(Int), save, create }

    private(set) var calls: [Call] = []
    var thread: Int?
    var text: String
    var failure: MPStorageTransportError?

    init(thread: Int?, text: String = FakeMPStorageRemote.emptyDocument) {
        self.thread = thread
        self.text = text
    }

    /// A `0.1` document with empty sections, as LOT-052 creates it.
    static let emptyDocument = """
        {"data":[{"blacklist":{"list":[]},"bookmarks":{"list":[]},"mpFlags":{"list":[]},"version":"0.1"}]}
        """

    func fail(with failure: MPStorageTransportError?) { self.failure = failure }

    func findThread() async throws(MPStorageTransportError) -> Int? {
        calls.append(.find)
        if let failure { throw failure }
        return thread
    }

    func read(post: Int) async throws(MPStorageTransportError) -> MPStorageSnapshot {
        calls.append(.read(post))
        if let failure { throw failure }
        guard post == thread else { throw .notAddressed }
        return try snapshot()
    }

    func save(
        _ ours: MPStorageDocument, base: MPStorageDocument?, at location: MPStorageLocation, stamp: MPStorageStamp
    ) async throws(MPStorageTransportError) -> MPStorageSaveResult {
        calls.append(.save)
        if let failure { throw failure }
        do {
            text = try MPStorageCodec.encodeForWriting(ours)
        } catch {
            throw .invalidDocument
        }
        return MPStorageSaveResult(snapshot: try snapshot(), conflicts: [], wrote: true)
    }

    func create(stamp: MPStorageStamp) async throws(MPStorageTransportError) -> MPStorageCreation {
        calls.append(.create)
        if let failure { throw failure }
        thread = thread ?? 99
        return .created(try snapshot())
    }

    private func snapshot() throws(MPStorageTransportError) -> MPStorageSnapshot {
        guard let thread, let document = try? MPStorageCodec.decode(text) else { throw .invalidDocument }
        return MPStorageSnapshot(
            location: MPStorageLocation(post: thread, numreponse: 1, editURL: URL(fileURLWithPath: "/edit")), text: text,
            document: document
        )
    }
}

/// A login state the tests flip.
final class MPStorageLogin: @unchecked Sendable {
    private let lock = NSLock()
    private var flag = true
    var value: Bool {
        get { lock.withLock { flag } }
        set { lock.withLock { flag = newValue } }
    }
}

@MainActor
struct MPStorageSyncModelTests {
    nonisolated static let now = Date(timeIntervalSince1970: 1_800_000_000)
    nonisolated static let account = "Alice"

    struct Fixture {
        let model: MPStorageSyncModel
        let remote: FakeMPStorageRemote
        let settings: InMemorySettingsStore
        let copies: MPStorageCopyStore
        let login: MPStorageLogin

        var states: MPStorageSyncStateStore { MPStorageSyncStateStore(settings: settings) }
        var persistence: MPStorageCopyPersistence { MPStorageCopyPersistence(store: copies, account: MPStorageSyncModelTests.account) }
    }

    static func make(
        thread: Int?, state: MPStorageSyncState? = nil, copy: MPStorageCopy = MPStorageCopy(),
        text: String = FakeMPStorageRemote.emptyDocument
    ) async throws -> Fixture {
        let remote = FakeMPStorageRemote(thread: thread, text: text)
        let settings = InMemorySettingsStore()
        let states = MPStorageSyncStateStore(settings: settings)
        if let state { states.set(state, for: account, at: now.addingTimeInterval(-60)) }
        let copies = MPStorageCopyStore(persistence: InMemorySmallStorePersistence<MPStorageCopyDocument>())
        try await copies.save(copy, for: account)
        let login = MPStorageLogin()
        let model = MPStorageSyncModel(
            account: account,
            sync: MPStorageSync(remote: remote, persistence: MPStorageCopyPersistence(store: copies, account: account)),
            states: states, isLoggedIn: { login.value }, clock: { now }
        )
        return Fixture(model: model, remote: remote, settings: settings, copies: copies, login: login)
    }

    // MARK: Start

    @Test func anUnaskedAccountWithAThreadTurnsOnByItself() async throws {
        let fixture = try await Self.make(thread: 7)
        await fixture.model.start()
        #expect(fixture.model.record == MPStorageSyncRecord(state: .on, decidedAt: Self.now))
        #expect(fixture.model.lastSync == Self.now)
        #expect(await fixture.remote.calls == [.find, .read(7)])
        #expect(fixture.model.status == .idle)
    }

    @Test func anUnaskedAccountWithoutAThreadStaysUnaskedAndSearchesOncePerDay() async throws {
        let fixture = try await Self.make(thread: nil)
        await fixture.model.start()
        #expect(fixture.model.record == .unasked)
        #expect(await fixture.remote.calls == [.find])
        // Another session of the same account the same day: no new walk of the MP list.
        let again = MPStorageSyncModel(
            account: Self.account,
            sync: MPStorageSync(remote: fixture.remote, persistence: fixture.persistence),
            states: fixture.states, isLoggedIn: { true }, clock: { Self.now.addingTimeInterval(3_600) }
        )
        await again.start()
        #expect(await fixture.remote.calls == [.find])
    }

    @Test(arguments: [MPStorageSyncState.declined, .off])
    func aDecidedAccountIsNeverContactedAtStart(_ state: MPStorageSyncState) async throws {
        let fixture = try await Self.make(thread: 7, state: state)
        await fixture.model.start()
        #expect(await fixture.remote.calls.isEmpty)
        #expect(fixture.model.record?.state == state)
    }

    @Test func anOnAccountSyncsAtStartOnlyOnce() async throws {
        let fixture = try await Self.make(thread: 7, state: .on, copy: MPStorageCopy(post: 7))
        await fixture.model.start()
        await fixture.model.start()
        #expect(await fixture.remote.calls == [.read(7)])
        #expect(fixture.model.lastSync == Self.now)
    }

    @Test func loggedOutNothingIsFetched() async throws {
        let fixture = try await Self.make(thread: 7, state: .on, copy: MPStorageCopy(post: 7))
        fixture.login.value = false
        await fixture.model.start()
        #expect(await fixture.remote.calls.isEmpty)
    }

    @Test func anUnreadableStateIsLeftAlone() async throws {
        let fixture = try await Self.make(thread: 7)
        fixture.settings.setRawValue(.string("paused"), forKey: "mpstorage.alice")
        let model = MPStorageSyncModel(
            account: Self.account,
            sync: MPStorageSync(remote: fixture.remote, persistence: fixture.persistence),
            states: fixture.states, isLoggedIn: { true }, clock: { Self.now }
        )
        await model.start()
        #expect(model.record == nil)
        #expect(model.writeConsent() == .deviceOnly)
        #expect(await fixture.remote.calls.isEmpty)
        #expect(fixture.settings.rawValue(forKey: "mpstorage.alice") == .string("paused"))
    }

    // MARK: Réglages

    @Test func switchingOnWithAThreadTurnsOn() async throws {
        let fixture = try await Self.make(thread: 7, state: .off)
        await fixture.model.setEnabled(true)
        #expect(fixture.model.isOn)
        #expect(!fixture.model.asksCreation)
        #expect(await fixture.remote.calls.contains(.create) == false)
    }

    @Test func switchingOnWithoutAThreadAsksBeforeCreating() async throws {
        let fixture = try await Self.make(thread: nil, state: .off)
        await fixture.model.setEnabled(true)
        #expect(fixture.model.asksCreation)
        #expect(!fixture.model.isOn)
        #expect(await fixture.remote.calls == [.find])
        await fixture.model.answerCreation(true)
        #expect(fixture.model.isOn)
        #expect(!fixture.model.asksCreation)
        #expect(await fixture.remote.calls == [.find, .create])
    }

    @Test func decliningTheCreationIsRememberedForThisAccountOnly() async throws {
        let fixture = try await Self.make(thread: nil)
        await fixture.model.setEnabled(true)
        await fixture.model.answerCreation(false)
        #expect(fixture.model.record == MPStorageSyncRecord(state: .declined, decidedAt: Self.now))
        #expect(fixture.states.record(for: "Bob") == .unasked)
        #expect(await fixture.remote.calls.contains(.create) == false)
    }

    @Test func aFailedCreationLeavesTheStateAsItWas() async throws {
        let fixture = try await Self.make(thread: nil)
        await fixture.model.setEnabled(true)
        await fixture.remote.fail(with: .posting(.rejected(message: nil)))
        await fixture.model.answerCreation(true)
        #expect(fixture.model.record == .unasked)
        #expect(fixture.model.status == .failed("La synchronisation du stockage MP a échoué."))
    }

    @Test func switchingOffDeletesNothing() async throws {
        let copy = MPStorageCopy(post: 7, base: FakeMPStorageRemote.emptyDocument, lastSync: Self.now)
        let fixture = try await Self.make(thread: 7, state: .on, copy: copy)
        await fixture.model.setEnabled(false)
        #expect(fixture.model.record?.state == .off)
        #expect(await fixture.copies.copy(for: Self.account) == copy)
        #expect(await fixture.remote.calls.isEmpty)
    }

    @Test func switchingOnLoggedOutSaysSo() async throws {
        let fixture = try await Self.make(thread: 7, state: .off)
        fixture.login.value = false
        await fixture.model.setEnabled(true)
        #expect(fixture.model.status == .failed("Connectez-vous pour activer le stockage MP."))
        #expect(await fixture.remote.calls.isEmpty)
    }

    @Test func aMissingThreadIsSaid() async throws {
        let fixture = try await Self.make(thread: nil, state: .on, copy: MPStorageCopy(post: 7))
        await fixture.model.resync()
        #expect(fixture.model.threadMissing)
        #expect(fixture.model.status == .failed("Le MP de stockage est introuvable."))
    }

    @Test func aNetworkFailureIsSaidWithoutDetails() async throws {
        let fixture = try await Self.make(thread: 7, state: .on, copy: MPStorageCopy(post: 7))
        await fixture.remote.fail(with: .network(.offline))
        await fixture.model.resync()
        #expect(fixture.model.status == .failed("Réseau indisponible : la synchronisation reprendra plus tard."))
    }

    // MARK: Writes (LOT-131, LOT-132)

    @Test func theWriteConsentFollowsTheState() async throws {
        #expect(try await Self.make(thread: nil).model.writeConsent() == .ask)
        #expect(try await Self.make(thread: nil, state: .on).model.writeConsent() == .sync)
        #expect(try await Self.make(thread: nil, state: .declined).model.writeConsent() == .deviceOnly)
        #expect(try await Self.make(thread: nil, state: .off).model.writeConsent() == .deviceOnly)
    }

    @Test func anEditIsWrittenWhileOn() async throws {
        let fixture = try await Self.make(
            thread: 7, state: .on, copy: MPStorageCopy(post: 7, base: FakeMPStorageRemote.emptyDocument)
        )
        let changed = await fixture.model.edit { document, stamp in try document.addBlocklistEntry(username: "user9", stamp: stamp) }
        #expect(changed)
        #expect(await fixture.remote.calls == [.read(7), .save])
        #expect(fixture.model.document?.data.first?.blocklist?.list.map(\.username) == ["user9"])
    }

    @Test func noEditWhileNotOn() async throws {
        let fixture = try await Self.make(
            thread: 7, state: .declined, copy: MPStorageCopy(post: 7, base: FakeMPStorageRemote.emptyDocument)
        )
        let changed = await fixture.model.edit { document, stamp in try document.addBlocklistEntry(username: "user9", stamp: stamp) }
        #expect(!changed)
        #expect(await fixture.copies.copy(for: Self.account)?.pending == nil)
    }

    // MARK: Flags

    static func flagged(_ flags: [MPStorageMPFlag]) throws -> String {
        var document = try MPStorageCodec.decode(FakeMPStorageRemote.emptyDocument)
        for flag in flags { _ = try document.upsertMPFlag(flag, stamp: MPStorageStamp(date: now)) }
        return try MPStorageCodec.encodeForWriting(document)
    }

    @Test func flagsShowOnlyOnGroupRowsWhileOn() async throws {
        let text = try Self.flagged([MPStorageMPFlag(topic: 31, pValue: "1", href: "t555", page: 2), MPStorageMPFlag(topic: 30, page: 1)])
        let fixture = try await Self.make(thread: 7, state: .on, copy: MPStorageCopy(post: 7, base: text), text: text)
        await fixture.model.start()
        #expect(fixture.model.flag(for: messageThread(31, group: true))?.href == "t555")
        #expect(fixture.model.flag(for: messageThread(30)) == nil) // one-to-one
        await fixture.model.setEnabled(false)
        #expect(fixture.model.flag(for: messageThread(31, group: true)) == nil)
    }

    @Test func aFlagWithoutPageIsIgnored() async throws {
        let text = try Self.flagged([MPStorageMPFlag(topic: 31, href: "t555")])
        let fixture = try await Self.make(thread: 7, state: .on, copy: MPStorageCopy(post: 7, base: text), text: text)
        await fixture.model.start()
        #expect(fixture.model.flag(for: messageThread(31, group: true)) == nil)
    }

    @Test func theSettingsSayTheStateInWords() {
        #expect(MPStorageSettingsRows.stateText(.on) == "Activé pour ce compte")
        #expect(MPStorageSettingsRows.stateText(nil) == "État enregistré illisible")
        #expect(MPStorageSettingsRows.lastSyncText(nil) == "Jamais")
    }
}
