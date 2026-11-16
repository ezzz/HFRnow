import Dispatch
import Foundation
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Synchronization
import Testing

/// A list file whose saves wait while the gate is closed, so a test can hold a toggle in the middle of its write.
private final class HeldPseudoListPersistence: PseudoListPersistence {
    private let inner = InMemoryPseudoListPersistence()
    private let closed = Mutex(false)
    private let gate = DispatchSemaphore(value: 0)
    func close() { closed.withLock { $0 = true } }
    func open() { if closed.withLock({ let was = $0; $0 = false; return was }) { gate.signal() } }
    func load() throws -> PseudoListDocument? { try inner.load() }
    func save(_ document: PseudoListDocument) throws {
        if closed.withLock({ $0 }) { gate.wait() }
        try inner.save(document)
    }
    func quarantineUnreadableData() throws { try inner.quarantineUnreadableData() }
}

/// #652: a tap on a message's author opens the profile, with legacy's quick actions (`userProfileQuickActions`,
/// `MessagesView.swift:4387-4412` @ 87fe0d1c), and a quick action closes it before acting (`:4422-4490`).
@MainActor
struct AuthorProfileFlowTests {
    private static let profileLink = url("https://forum.hardware.fr/hfr/profil-910002.htm")
    private static let mpLink = url("https://forum.hardware.fr/message.php?config=hfr.inc&cat=prive&dest=auteur")
    private static let edit = url("https://forum.hardware.fr/message.php?config=hfr.inc&cat=13&post=28563&numreponse=7")

    @MainActor
    private struct Fixture {
        let flow = AuthorMenuFlow()
        let store = PseudoListStore(persistence: InMemoryPseudoListPersistence())
        let composer = ComposerFixture.services(poster: ScriptedPoster([]))
    }

    private func context(author: String = "auteur", own: Bool = false, mpLink: URL? = mpLink) -> MessageMenuContext {
        MessageMenuContext(
            numreponse: 7, author: author,
            actions: MessageActions(editURL: own ? Self.edit : nil, profileURL: Self.profileLink, privateMessageURL: mpLink),
            permalinkURL: nil
        )
    }

    /// The profile model the reader would build, on R56b, with lists for account "moi".
    private func profileModel(
        store: PseudoListStore, rebuild: @escaping @MainActor () -> Void = {}
    ) throws -> UserProfileModel {
        let profile = try UserProfileModelTests.captured("R56b-profile-other-member-anon.html")
        let model = UserProfileModel(
            memberID: 910_002, source: FakeUserProfiles([.success(profile)]), lists: PseudoListManager(store: store, account: "moi")
        )
        model.onListsChanged = rebuild
        return model
    }

    /// The whole route: the author tap of a message with a profile link puts that member's profile on screen, tied to the message.
    @Test func theAvatarTapShowsTheMembersProfileForThatMessage() async throws {
        let fixture = Fixture()
        let mpLink = Self.mpLink
        let pages = FakeTopicPages { _ in
            ReaderPage(
                topicID: readerTopic, title: "Sujet", currentPage: 1, maxPage: 1,
                messages: [ReaderMessage(
                    numreponse: 7, author: "auteur", isDeleted: false, isContinuation: false, avatarURL: nil,
                    dateText: "27-10-2026 10:00:00", editNote: nil, quotedByCount: nil, content: MessageContent(html: "<p>x</p>"),
                    actions: MessageActions(profileURL: Self.profileLink, privateMessageURL: mpLink)
                )],
                pageURL: url("https://forum.hardware.fr/hfr/Discussions/Cuisine/pizza-maison-sujet_28563_1.htm")
            )
        }
        let reader = TopicReaderModel(target: ReaderTarget(source: .topic(readerTopic), page: 1), source: pages)
        await reader.onAppear()
        var built: [Int] = []
        let store = fixture.store
        reader.install(MessageActionRegistry(fixture.flow.handlers(
            reader: reader, composer: fixture.composer,
            makeProfile: { id in
                built.append(id)
                return UserProfileModel(memberID: id, source: FakeUserProfiles([]), lists: PseudoListManager(store: store, account: "moi"))
            },
            confirm: { _ in }
        )))
        await reader.openMenu(post: 7, source: .avatar, token: try #require(reader.document?.token))
        #expect(reader.presentedMenu == nil)
        #expect(built == [910_002] && fixture.flow.profile?.memberID == 910_002)
        #expect(fixture.flow.profile?.origin == ProfileMessageOrigin(author: "auteur", isOwnMessage: false))
        #expect(fixture.flow.profile?.onPrivateMessage != nil)
    }

    /// Another member's post: MP and both lists, on the message's author.
    @Test func anotherMembersPostOffersMPAndTheLists() async throws {
        let fixture = Fixture()
        let model = try profileModel(store: fixture.store)
        fixture.flow.showProfile(model, from: context(), composer: fixture.composer, confirm: { _ in })
        await model.onAppear()
        #expect(model.privateMessageRecipient != nil)
        #expect(model.listPseudo == "auteur" && model.offers(.blocklist) && model.offers(.allowlist))
    }

    /// The user's own post: the profile, without MP or lists (legacy `isOwnMessage`).
    @Test func theUsersOwnPostOffersNeitherMPNorTheLists() async throws {
        let fixture = Fixture()
        let model = try profileModel(store: fixture.store)
        fixture.flow.showProfile(model, from: context(own: true), composer: fixture.composer, confirm: { _ in })
        await model.onAppear()
        #expect(model.onPrivateMessage == nil && model.privateMessageRecipient == nil)
        #expect(model.listPseudo == nil && !model.offers(.blocklist) && !model.offers(.allowlist))
    }

    /// A message whose author is blank: MP stays (it follows the link), the lists go (legacy `usableAuthorName`).
    @Test func aBlankAuthorOffersMPButNoList() async throws {
        let fixture = Fixture()
        let model = try profileModel(store: fixture.store)
        fixture.flow.showProfile(model, from: context(author: "  "), composer: fixture.composer, confirm: { _ in })
        await model.onAppear()
        #expect(model.privateMessageRecipient != nil)
        #expect(model.listPseudo == nil && !model.offers(.allowlist))
    }

    /// Logged out (no composer) or without a private-message link: no MP.
    @Test func noComposerOrNoLinkMeansNoMP() async throws {
        let fixture = Fixture()
        let loggedOut = try profileModel(store: fixture.store)
        fixture.flow.showProfile(loggedOut, from: context(), composer: nil, confirm: { _ in })
        await loggedOut.onAppear()
        #expect(loggedOut.privateMessageRecipient == nil)
        let noLink = try profileModel(store: fixture.store)
        fixture.flow.showProfile(noLink, from: context(mpLink: nil), composer: fixture.composer, confirm: { _ in })
        await noLink.onAppear()
        #expect(noLink.privateMessageRecipient == nil)
    }

    /// "MP" closes the profile; the composer opens once the sheet is gone, addressed from the message's link.
    @Test func mpClosesTheProfileThenOpensTheComposer() async throws {
        let fixture = Fixture()
        let model = try profileModel(store: fixture.store)
        fixture.flow.showProfile(model, from: context(), composer: fixture.composer, confirm: { _ in })
        await model.onAppear()
        model.writePrivateMessage()
        #expect(fixture.flow.profile == nil && fixture.flow.newMessage == nil)
        fixture.flow.profileDidClose()
        guard case .newPrivateMessage(let target)? = fixture.flow.newMessage?.target else {
            Issue.record("no MP composer")
            return
        }
        #expect(target.recipient == "auteur" && target.formURL == Self.mpLink)
        fixture.flow.profileDidClose()
        #expect(fixture.flow.newMessage != nil, "runs once")
    }

    /// A list toggle closes the profile, rebuilds the reader's page and tells the result from the reader once the sheet is gone;
    /// the profile shows no sentence of its own (VoiceOver hears it once).
    @Test func aToggleClosesTheProfileRebuildsThePageAndTellsTheResult() async throws {
        let fixture = Fixture()
        var rebuilds = 0
        var confirmed: [String] = []
        let model = try profileModel(store: fixture.store) { rebuilds += 1 }
        fixture.flow.showProfile(model, from: context(), composer: fixture.composer) { confirmed.append($0) }
        await model.onAppear()
        await model.toggle(.blocklist)
        #expect(fixture.flow.profile == nil)
        #expect(rebuilds == 1)
        #expect(await fixture.store.isBlocked("auteur", account: "moi"))
        #expect(confirmed.isEmpty, "told once the sheet is gone")
        #expect(model.listFeedback == nil && model.listFeedbackCount == 0)
        fixture.flow.profileDidClose()
        #expect(confirmed == ["BIM! auteur ajouté à la liste noire"])
    }

    /// The user closed the profile while the toggle was written: the result is told at once, and nothing stays pending for the
    /// next profile (review round 1, finding 1).
    @Test func aToggleThatEndsAfterTheUserClosedTheProfileTellsAtOnce() async throws {
        let fixture = Fixture()
        var confirmed: [String] = []
        let model = try profileModel(store: fixture.store)
        fixture.flow.showProfile(model, from: context(), composer: fixture.composer) { confirmed.append($0) }
        await model.onAppear()
        fixture.flow.profile = nil // "Fermer"
        fixture.flow.profileDidClose()
        await model.toggle(.allowlist)
        #expect(confirmed == ["BOUM BOUM ! auteur ajouté à la love list \u{2665}"])
        let next = try profileModel(store: fixture.store)
        fixture.flow.show(next)
        fixture.flow.profile = nil
        fixture.flow.profileDidClose()
        #expect(confirmed.count == 1, "no stale toast")
    }

    /// "MP" left the profile (its composer waits for the dismissal) and a toggle of that profile ends meanwhile: the toast is told
    /// and the composer still opens (review round 2, finding 1).
    @Test func aToggleEndingAfterMPKeepsTheComposerPending() async throws {
        let fixture = Fixture()
        var confirmed: [String] = []
        let model = try profileModel(store: fixture.store)
        fixture.flow.showProfile(model, from: context(), composer: fixture.composer) { confirmed.append($0) }
        await model.onAppear()
        model.writePrivateMessage()
        await model.toggle(.allowlist)
        #expect(confirmed.count == 1)
        fixture.flow.profileDidClose()
        #expect(fixture.flow.newMessage != nil)
    }

    /// Another profile is on screen when a toggle of the first ends: that profile stays, the toast is told at once (round 2,
    /// finding 2).
    @Test func aToggleOfAProfileNoLongerShownLeavesTheShownOneOpen() async throws {
        let fixture = Fixture()
        var confirmed: [String] = []
        let first = try profileModel(store: fixture.store)
        fixture.flow.showProfile(first, from: context(), composer: fixture.composer) { confirmed.append($0) }
        await first.onAppear()
        let second = try profileModel(store: fixture.store)
        fixture.flow.showProfile(second, from: context(author: "autre"), composer: fixture.composer) { confirmed.append($0) }
        await first.toggle(.allowlist)
        #expect(fixture.flow.profile === second)
        #expect(confirmed.count == 1)
        fixture.flow.profileDidClose()
        #expect(confirmed.count == 1, "nothing deferred to the second profile")
    }

    /// A second tap while the first toggle is written does nothing: one toggle, one sentence (round 2, finding 3).
    @Test func aSecondTapDuringAToggleIsIgnored() async throws {
        let persistence = HeldPseudoListPersistence()
        let store = PseudoListStore(persistence: persistence)
        let model = try profileModel(store: store)
        await model.onAppear()
        persistence.close()
        let first = Task { await model.toggle(.blocklist) }
        await Task.yield()
        let second = Task { await model.toggle(.blocklist) }
        await Task.yield()
        persistence.open()
        await first.value
        await second.value
        #expect(model.listFeedbackCount == 1 && model.isBlocked)
    }

    /// The MP button follows the message even when a hook is set: never on the user's own post (review round 1, finding 4).
    @Test func theMPButtonIsHiddenOnTheUsersOwnPostWhateverTheHook() async throws {
        let fixture = Fixture()
        let model = try profileModel(store: fixture.store)
        model.onPrivateMessage = { _ in }
        model.origin = ProfileMessageOrigin(author: "auteur", isOwnMessage: true)
        await model.onAppear()
        #expect(model.privateMessageRecipient == nil)
        model.origin = ProfileMessageOrigin(author: "auteur", isOwnMessage: false)
        #expect(model.privateMessageRecipient != nil)
    }

    /// A profile opened from a link keeps LOT-118's behaviour: it stays open and says the result itself.
    @Test func aProfileFromALinkStaysOpenAfterAToggle() async throws {
        let fixture = Fixture()
        let profile = try UserProfileModelTests.captured("R56b-profile-other-member-anon.html")
        let model = try profileModel(store: fixture.store)
        fixture.flow.show(model)
        await model.onAppear()
        await model.toggle(.allowlist)
        #expect(fixture.flow.profile === model)
        #expect(model.listPseudo == profile.pseudo && model.listFeedback != nil)
    }
}
