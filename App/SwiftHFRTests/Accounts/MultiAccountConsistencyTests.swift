import Foundation
import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Testing

/// LOT-156: what follows the selected account and was not covered by LOT-081's rebuild of the screens: a send started before a
/// switch keeps its account (Q-8), the app icon badge never shows another account's count, and the accounts screen says when a
/// session lapses.
@MainActor
struct MultiAccountConsistencyTests {
    // MARK: - Q-8: a switch during a send

    // A composer open as user1 keeps user1's session and drafts after a switch to user2: its send posts as the account shown
    // when it started, never as the new one. Giving every environment the current session (instead of its own) fails it.
    @Test func aSwitchLeavesTheComposerOfThePreviousAccountOnItsOwnSession() async throws {
        let store = try InMemoryCredentialStore(accounts: [Fake.account("user1", main: true), Fake.account("user2")])
        let model = makeModel(store: store)
        await model.restore()
        let before = AppEnvironment.current(of: model)
        let composer = try #require(before.composer)
        let poster = try #require(composer.poster as? LiveReplyPoster)

        try model.select("user2")

        let first = try #require(model.session(for: "user1"))
        #expect(poster.session === first)
        #expect(composer.account == "user1")
        #expect(await poster.session.userKey() == "user1")
        let after = try #require(AppEnvironment.current(of: model).composer)
        let newPoster = try #require(after.poster as? LiveReplyPoster)
        #expect(newPoster.session === model.session(for: "user2"))
        #expect(newPoster.session !== first)
        #expect(after.account == "user2")
    }

    // The send of user1's composer, held at its POST while the account switches and user2's root opens the same topic: the
    // reply leaves once, with user1's text, the confirmation discards user1's draft only, and user2's draft is untouched.
    // Scoping the confirmed discard by anything but the composer's own account (the current one) fails it.
    @Test func aSendHeldAcrossASwitchDiscardsOnlyItsOwnAccountsDraft() async throws {
        let gate = ReaderGate()
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        try await drafts.save("Brouillon de user2", for: replyTarget.draftContext, account: "user2")
        let poster = ScriptedPoster([.success(replyConfirmed)], gate: gate)
        let first = ReplyComposerModel(
            target: replyTarget, services: ComposerFixture.services(poster: poster, drafts: drafts, account: "user1"),
            autosaveDelay: .seconds(60)
        )
        await first.start()
        first.update(text: "Réponse de user1")
        let send = Task { await first.send() }
        await gate.untilArrived()
        let second = ReplyComposerModel(
            target: replyTarget, services: ComposerFixture.services(poster: ScriptedPoster([]), drafts: drafts, account: "user2"),
            autosaveDelay: .seconds(60)
        )
        await second.start()
        await gate.open()
        await send.value

        #expect(poster.calls.map(\.text) == ["Réponse de user1"])
        #expect(first.closeReason == .sent(replyConfirmed))
        #expect(await ComposerFixture.storedText(drafts, account: "user1") == nil)
        #expect(await ComposerFixture.storedText(drafts, account: "user2") == "Brouillon de user2")
        #expect(second.text == "Brouillon de user2")
    }

    // MARK: - App icon badge

    // Only the first root of a window, with an account, leaves the icon alone (the background check set it for that account).
    @Test func aRootLoggedOutOrRebuiltClearsTheIconBadgeUntilItsCount() {
        let rebuilt = SidebarDestination.tab(.favorites)
        #expect(RootModel.clearsIconBadgeBeforeCount(accountName: "user1", initial: nil) == false)
        #expect(RootModel.clearsIconBadgeBeforeCount(accountName: "user1", initial: rebuilt))
        #expect(RootModel.clearsIconBadgeBeforeCount(accountName: nil, initial: nil))
        #expect(RootModel.clearsIconBadgeBeforeCount(accountName: nil, initial: rebuilt))
    }

    // Legacy resets `nb_mp` at every switch and logout; a root that left the icon alone kept user1's count under user2 or logged
    // out. Returning nil before a count whatever the root fails the first expectation.
    @Test func aClearingRootShowsZeroUntilAPageGivesItsCount() {
        let store = InMemorySettingsStore()
        let root = root(store: store, clears: true)
        #expect(root.appIconBadge == 0)
        root.privateMessageCount.record(4, ticket: root.privateMessageCount.ticket())
        #expect(root.appIconBadge == 4)
        store.set(false, for: SettingKey.privateMessageBadge)
        root.reloadSettings()
        #expect(root.appIconBadge == 0)
    }

    @Test func theLaunchRootStillLeavesTheBackgroundChecksBadgeAlone() {
        #expect(root(store: InMemorySettingsStore(), clears: false).appIconBadge == nil)
    }

    // The wiring of the root the app builds (`RootModel(environment:store:initial:)`): dropping the rule's argument there, or
    // reading another field than the environment's account, fails one of these.
    @Test func theAppsRootAppliesTheRuleToItsOwnAccountAndDestination() {
        let store = InMemorySettingsStore()
        #expect(RootModel(environment: environment(account: "fakeuser"), store: store).appIconBadge == nil)
        #expect(RootModel(environment: environment(account: "fakeuser"), store: store, initial: .tab(.messages)).appIconBadge == 0)
        #expect(RootModel(environment: environment(account: nil), store: store).appIconBadge == 0)
    }

    // MARK: - Session expiry

    @Test func theSessionExpiryIsTheEarliestLoginCookieExpiry() {
        let early = Date(timeIntervalSince1970: 2_000_000_000)
        let late = early.addingTimeInterval(86_400)
        let cookies = [
            StoredCookie(name: "md_user", value: "user1", domain: ".hardware.fr", expiresDate: late),
            StoredCookie(name: "md_passs", value: "fake-pass", domain: ".hardware.fr", expiresDate: early),
            // Neither another cookie nor the logout marker ends the session.
            StoredCookie(name: "p", value: "1", domain: ".hardware.fr", expiresDate: early.addingTimeInterval(-86_400)),
            StoredCookie(name: "md_user", value: "deleted", domain: ".forum.hardware.fr", expiresDate: Date(timeIntervalSince1970: 1))
        ]
        #expect(AccountRow.sessionExpiry(in: cookies) == early)
        #expect(AccountRow.sessionExpiry(in: [StoredCookie(name: "md_user", value: "user1", domain: ".hardware.fr")]) == nil)
        #expect(AccountRow.sessionExpiry(in: []) == nil)
    }

    @Test func eachRowCarriesItsOwnAccountsExpiry() async throws {
        // Whole seconds: the store encodes its dates.
        let first = Date(timeIntervalSince1970: 2_000_000_000)
        let second = first.addingTimeInterval(86_400)
        func account(_ user: String, expiry: Date, main: Bool) -> Account {
            let cookies = ["md_user": user, "md_passs": "fake-pass"].map {
                StoredCookie(name: $0.key, value: $0.value, domain: ".hardware.fr", expiresDate: expiry)
            }
            return Account(pseudo: user, displayName: nil, cookies: cookies, hashCheck: "fake-hash", isMain: main)
        }
        let store = try InMemoryCredentialStore(accounts: [
            account("user1", expiry: first, main: true), account("user2", expiry: second, main: false)
        ])
        let model = makeModel(store: store)
        await model.restore()
        let expiries = Dictionary(uniqueKeysWithValues: model.rows.map { ($0.id, $0.sessionExpiry) })
        #expect(expiries["user1"] == first)
        #expect(expiries["user2"] == second)
    }

    @Test func theStatusLineSaysWhenAConfirmedSessionLapses() throws {
        let expiry = try #require(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 12, day: 18, hour: 12)))
        let dayBefore = expiry.addingTimeInterval(-86_400)
        #expect(AccountRowView.statusText(.valid, expiry: expiry, now: dayBefore) == "Session valable jusqu’au 18 décembre")
        #expect(AccountRowView.statusText(.valid) == nil)
        // A date already past (a re-login whose store write failed keeps the old cookies stored) is not shown.
        #expect(AccountRowView.statusText(.valid, expiry: expiry, now: expiry) == nil)
        #expect(AccountRowView.statusText(.valid, expiry: expiry, now: expiry.addingTimeInterval(-1)) != nil)
        // Not confirmed by the forum: the stored date says nothing yet.
        #expect(AccountRowView.statusText(.restored, expiry: expiry) == nil)
        #expect(AccountRowView.statusText(.expired, expiry: expiry) == "Session expirée : reconnecte-toi")
    }

    // MARK: - Helpers

    /// The environment of a logged-out jar with fake lists, named after `account` (made up): nothing it builds reaches the forum.
    private func environment(account: String?) -> AppEnvironment {
        let live = AppEnvironment.make(session: HFRSession(), accountName: nil)
        return AppEnvironment(
            session: live.session, dataSource: FakeDataSource(), visibility: live.visibility, currentAccountName: account,
            topicPages: FakeTopicPages(), reader: live.reader, privateMessages: FakePrivateMessages(), composer: nil,
            filteredPosts: live.filteredPosts, favoriteStores: live.favoriteStores, flagActions: nil, memberAvatars: nil,
            pseudoListsSnapshot: live.pseudoListsSnapshot, blocklistChanges: nil, privateMessageCount: nil
        )
    }

    private func root(store: InMemorySettingsStore, clears: Bool) -> RootModel {
        let source = FakeDataSource()
        let forums = ForumListModel(dataSource: source)
        return RootModel(
            forums: forums,
            categories: NavigationModel(dataSource: source, forums: forums, startupSource: RootModel.categoriesStartupSource),
            favorites: NavigationModel(dataSource: source, forums: forums, startupSource: TopicSource(mode: .flagsAndFavorites)),
            messages: MessageListModel(source: FakePrivateMessages()), store: store, initial: .tab(.favorites),
            clearsIconBadgeBeforeCount: clears
        )
    }
}
