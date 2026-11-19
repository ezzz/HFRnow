import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Testing

/// `AccountsModel` over the real `AccountSync` and in-memory items (LOT-173): two models share one synchronizable item as
/// two devices of one Apple ID would.
@MainActor
struct AccountsModelSyncTests {
    private let item = InMemorySecureDataItem()

    private func device(
        _ accounts: [Account], login: ScriptedLogin = ScriptedLogin([]), state: InMemorySecureDataItem = InMemorySecureDataItem()
    ) throws -> (AccountsModel, InMemoryCredentialStore) {
        let store = try InMemoryCredentialStore(accounts: accounts)
        let sync = AccountSync(accounts: store, item: item, state: state)
        let model = AccountsModel(
            store: store, loginService: login, checker: ForumSessionCheck(refresher: ScriptedRefresher([:])),
            avatars: RecordingAvatars(), sync: sync
        )
        return (model, store)
    }

    @Test func theSwitchFollowsTheEngineAndIsOffByDefault() throws {
        let (model, _) = try device([Fake.account("user1", main: true)])
        model.reconcileAccountSync()
        #expect(!model.isAccountSyncOn)
        #expect(item.data == nil)
        model.setAccountSync(true)
        #expect(model.isAccountSyncOn)
        #expect(item.data != nil)
        model.setAccountSync(false)
        #expect(!model.isAccountSyncOn)
        #expect(model.accountSyncNotice == nil)
    }

    @Test func aRemovalIsSharedAndTheOtherDeviceDropsTheSession() async throws {
        let (deviceA, _) = try device([Fake.account("user1", main: true), Fake.account("user2")])
        let (deviceB, _) = try device([])
        await deviceA.restore()
        deviceA.setAccountSync(true)
        deviceB.reconcileAccountSync()
        await deviceB.restore()
        #expect(deviceB.rows.map(\.id) == ["user1", "user2"])
        #expect(deviceB.isAccountSyncOn)

        try deviceA.remove("user2")
        deviceB.reconcileAccountSync()
        #expect(deviceB.rows.map(\.id) == ["user1"])
        #expect(deviceB.session(for: "user2") == nil)
    }

    /// The session object stays (a new one would rebuild every screen of the current account): it adopts the cookies.
    @Test func credentialsReplacedOnAnotherDeviceAreAdoptedByTheSessionAndChecked() async throws {
        let script = LoginScript.success(
            userKey: "user1", displayName: "user1", cookies: Fake.cookies(user: "user1", pass: "fake-new"),
            hashCheck: "fake-hash-2", avatarURL: nil
        )
        let (deviceA, _) = try device([Fake.account("user1", main: true)], login: ScriptedLogin([script]))
        let (deviceB, _) = try device([])
        await deviceA.restore()
        deviceA.setAccountSync(true)
        deviceB.reconcileAccountSync()
        await deviceB.restore()
        let before = try #require(deviceB.session(for: "user1"))
        let generation = deviceB.currentSessionGeneration

        try await deviceA.logIn(pseudo: "user1", password: "fake-password", for: .existing(id: "user1", displayName: "user1"))
        deviceB.reconcileAccountSync()
        await deviceB.syncCheckTask?.value
        let after = try #require(deviceB.session(for: "user1"))
        #expect(after === before)
        #expect(deviceB.currentSessionGeneration == generation)
        #expect(await after.hashCheck == "fake-hash-2")
        #expect(await after.cookies().first { $0.name == "md_passs" }?.value == "fake-new")
    }

    @Test func aSwitchOffFromAnotherDeviceIsShownAndKeepsTheAccounts() async throws {
        let (deviceA, _) = try device([Fake.account("user1", main: true)])
        let (deviceB, _) = try device([Fake.account("user2", main: true)])
        deviceA.setAccountSync(true)
        deviceB.setAccountSync(true)
        await deviceB.restore()
        deviceA.setAccountSync(false)
        deviceB.reconcileAccountSync()
        #expect(!deviceB.isAccountSyncOn)
        #expect(deviceB.accountSyncNotice == AccountSyncMessages.switchedOff(.tombstone))
        #expect(deviceB.rows.map(\.id).contains("user2"))
    }

    @Test func aRefreshThatChangesNothingIsNotReported() async throws {
        let (model, store) = try device([Fake.account("user1", main: true)])
        await model.restore()
        model.setAccountSync(true)
        // The first write-back stores the jar's form of the cookies (expiries rounded to the second): a real change, shared.
        await model.persistSession(of: "user1")
        let writes = item.writeCount
        await model.persistSession(of: "user1")
        #expect(item.writeCount == writes)
        #expect(try store.load().accounts.count == 1)
    }

    @Test func anUnreadableCopyIsShownAndChangesNothing() throws {
        let (model, store) = try device([Fake.account("user1", main: true)])
        item.data = Data("not json".utf8)
        let before = store.envelope
        model.setAccountSync(true)
        #expect(!model.isAccountSyncOn)
        #expect(model.accountSyncNotice == AccountSyncMessages.problem(CredentialStoreError.corrupted))
        #expect(item.data == Data("not json".utf8))
        #expect(store.envelope == before)
    }

    @Test("#1200 P3: a state a later version wrote is shown, the switch stays off, no reset is offered, and the state is kept")
    func aLaterVersionStateIsShownAndKept() throws {
        let later = Data(#"{"version":2,"isOn":true,"enabledAt":1}"#.utf8)
        let state = InMemorySecureDataItem(data: later)
        let (model, _) = try device([Fake.account("user1", main: true)], state: state)
        model.reconcileAccountSync()
        #expect(!model.isAccountSyncDamaged)
        model.setAccountSync(true)
        model.setAccountSync(false)
        #expect(!model.isAccountSyncOn)
        #expect(!model.isAccountSyncDamaged)
        #expect(model.accountSyncNotice == AccountSyncMessages.problem(AccountSyncError.stateFromLaterVersion))
        #expect(state.data == later)
        #expect(item.writeCount == 0)
    }

    @Test("#1200 P3: damaged state bytes are shown with a reset; nothing changes until the user resets them")
    func aDamagedStateOffersAResetAndKeepsTheBytesUntilThen() throws {
        let damaged = Data("garbage".utf8)
        let state = InMemorySecureDataItem(data: damaged)
        let (model, _) = try device([Fake.account("user1", main: true)], state: state)
        model.reconcileAccountSync()
        model.setAccountSync(true)
        #expect(model.isAccountSyncDamaged)
        #expect(!model.isAccountSyncOn)
        #expect(model.accountSyncNotice == AccountSyncMessages.problem(AccountSyncError.damagedState))
        #expect(state.data == damaged)
        #expect(item.writeCount == 0)
    }

    @Test("#1200 P3: a state damaged while the switch showed on reads off, so turning it off is never an unconfirmed reset")
    func aStateDamagedWhileOnShowsTheSwitchOff() throws {
        let state = InMemorySecureDataItem()
        let (model, _) = try device([Fake.account("user1", main: true)], state: state)
        model.setAccountSync(true)
        #expect(model.isAccountSyncOn)
        state.data = Data("garbage".utf8)
        model.reconcileAccountSync()
        #expect(!model.isAccountSyncOn)
        #expect(model.isAccountSyncDamaged)
        #expect(state.data == Data("garbage".utf8))
    }

    @Test("#1200 P3: the user's reset writes a fresh off state, keeps the accounts and never touches the iCloud item")
    func theResetClearsADamagedState() throws {
        let state = InMemorySecureDataItem(data: Data("garbage".utf8))
        let (model, store) = try device([Fake.account("user1", main: true)], state: state)
        model.reconcileAccountSync()
        let accounts = store.envelope
        model.resetAccountSync()
        #expect(!model.isAccountSyncDamaged)
        #expect(!model.isAccountSyncOn)
        #expect(model.accountSyncNotice == nil)
        #expect(state.data != Data("garbage".utf8))
        #expect(item.writeCount == 0)
        #expect(store.envelope == accounts)
        // The switch works again once the state is reset.
        model.setAccountSync(true)
        #expect(model.isAccountSyncOn)
    }
}
