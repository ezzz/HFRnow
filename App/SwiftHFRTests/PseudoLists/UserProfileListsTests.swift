import Foundation
import HFRStorage
@testable import SwiftHFR
import Testing

/// The profile buttons (LOT-118).
@MainActor
struct UserProfileListsTests {
    private func model(account: String?) async throws -> (UserProfileModel, PseudoListStore) {
        let profile = try UserProfileModelTests.captured("R56b-profile-other-member-anon.html")
        let store = PseudoListStore(persistence: InMemoryPseudoListPersistence())
        let lists = PseudoListManager(store: store, account: account)
        let model = UserProfileModel(memberID: 1, source: FakeUserProfiles([.success(profile)]), lists: lists)
        await model.onAppear()
        return (model, store)
    }

    @Test func theButtonsAppearOnceTheProfileNamesTheMemberAndToggleWithTheirState() async throws {
        let profile = try UserProfileModelTests.captured("R56b-profile-other-member-anon.html")
        let store = PseudoListStore(persistence: InMemoryPseudoListPersistence())
        let model = UserProfileModel(
            memberID: 1, source: FakeUserProfiles([.success(profile)]),
            lists: PseudoListManager(store: store, account: "moi")
        )
        var rebuilds = 0
        model.onListsChanged = { rebuilds += 1 }
        #expect(!model.offers(.blocklist) && !model.offers(.allowlist))
        await model.onAppear()
        #expect(model.offers(.blocklist) && model.offers(.allowlist) && !model.isBlocked && rebuilds == 0)
        await model.toggle(.blocklist)
        #expect(rebuilds == 1)
        #expect(model.isBlocked && model.listFeedback == "BIM! \(profile.pseudo) ajouté à la liste noire")
        #expect(await store.isBlocked(profile.pseudo, account: "moi"))
        await model.toggle(.blocklist)
        #expect(!model.isBlocked)
    }

    @Test func loggedOutOnlyTheAllowlistButtonIsOffered() async throws {
        let (model, _) = try await model(account: nil)
        #expect(!model.offers(.blocklist) && model.offers(.allowlist))
    }

    @Test func theAccountsOwnProfileOffersNoList() async throws {
        let profile = try UserProfileModelTests.captured("R56b-profile-other-member-anon.html")
        let store = PseudoListStore(persistence: InMemoryPseudoListPersistence())
        let lists = PseudoListManager(store: store, account: profile.pseudo.lowercased())
        let model = UserProfileModel(memberID: 1, source: FakeUserProfiles([.success(profile)]), lists: lists)
        await model.onAppear()
        #expect(!model.offers(.blocklist) && !model.offers(.allowlist))
    }

    // LOT-159 (Fable r1290 #1): the account key as HFR sets it, URL-encoded (every byte, so the raw key never matches).
    // LOT-159 D3 (#1297): logged out, the profile says to sign in to block, and asks its sheet to open the login.
    @Test func loggedOutTheProfileSaysToSignInToBlockAndOpensTheLogin() async throws {
        let (model, _) = try await model(account: nil)
        #expect(model.offersSignInToBlock && !model.offers(.blocklist))
        #expect(!model.wantsSignIn)
        model.requestSignIn()
        #expect(model.wantsSignIn)
    }

    @Test func loggedInTheProfileOffersNoSignInEntry() async throws {
        let (model, _) = try await model(account: "moi")
        #expect(!model.offersSignInToBlock)
        model.requestSignIn()
        #expect(!model.wantsSignIn)
    }

    @Test func theSignInEntryWaitsForTheMemberToBeNamed() async throws {
        let store = PseudoListStore(persistence: InMemoryPseudoListPersistence())
        let model = UserProfileModel(
            memberID: 1, source: FakeUserProfiles([]), lists: PseudoListManager(store: store, account: nil)
        )
        #expect(!model.offersSignInToBlock)
    }

    @Test func theAccountsOwnProfileOffersNoListWithAURLEncodedKey() async throws {
        let profile = try UserProfileModelTests.captured("R56b-profile-other-member-anon.html")
        let encoded = profile.pseudo.utf8.map { String(format: "%%%02X", $0) }.joined()
        let store = PseudoListStore(persistence: InMemoryPseudoListPersistence())
        let lists = PseudoListManager(store: store, account: encoded)
        let model = UserProfileModel(memberID: 1, source: FakeUserProfiles([.success(profile)]), lists: lists)
        await model.onAppear()
        #expect(!model.offers(.blocklist) && !model.offers(.allowlist))
    }
}
