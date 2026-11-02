import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Testing

/// The new-MP link of a profile or of a message's "MP" action (`R45b` meta, HFR-PROTOCOL §6 profile links).
let newMessageLink = url("https://forum.hardware.fr/message.php?config=hfr.inc&cat=prive&sond=&p=1&subcat=&dest=user1&subcatgroup=0")

/// The target of `newMessageLink`.
let newMessageTarget: NewMessageTarget = {
    guard let target = NewMessageTarget(link: newMessageLink) else { preconditionFailure("The R45b link is a new-MP link") }
    return target
}()

/// HFR's confirmation of a new private message (`W10`, HFR-PROTOCOL §7 E15): it refreshes to the list, no thread named.
let newMessageConfirmed = PostingResult(
    action: .newPrivateMessage, message: "Votre message a été posté avec succès !",
    refreshURL: url("https://forum.hardware.fr/forum1.php?config=hfr.inc&cat=prive&page=1&subcat=0&sondage=0&owntopic=0")
)

/// The new private message composer (LOT-128): recipient, subject and text, its draft, and what it sends.
@MainActor
struct NewMessageComposerTests {
    private let target = newMessageTarget

    private func composer(
        _ poster: ScriptedPoster, drafts: DraftStore = DraftStore(persistence: InMemoryDraftPersistence())
    ) -> ReplyComposerModel {
        ReplyComposerModel(
            composing: .newPrivateMessage(target), services: ComposerFixture.services(poster: poster, drafts: drafts),
            autosaveDelay: .seconds(60)
        )
    }

    // MARK: Target

    @Test func theLinkNamesTheRecipientAndTheListButtonNobody() throws {
        #expect(target.recipient == "user1")
        #expect(target.formURL == newMessageLink)
        #expect(target.draftContext == .privateMessage(recipient: "user1"))
        // The MP list's `md_btn_new_topic` (`R13a`): `dest=` empty.
        let list = try #require(NewMessageTarget(link: url(
            "https://forum.hardware.fr/message.php?config=hfr.inc&cat=prive&sond=0&p=1&subcat=0&dest=&subcatgroup=0"
        )))
        #expect(list.recipient.isEmpty)
    }

    @Test(arguments: [
        "http://forum.hardware.fr/message.php?config=hfr.inc&cat=prive&dest=user1",
        "https://forum.hardware.fr:8443/message.php?config=hfr.inc&cat=prive&dest=user1",
        "https://example.invalid/message.php?config=hfr.inc&cat=prive&dest=user1",
        "https://forum.hardware.fr/message.php?config=hfr.inc&cat=13&dest=user1"
    ])
    func aLinkOffTheForumOrNotPrivateIsNoTarget(_ link: String) {
        #expect(NewMessageTarget(link: url(link)) == nil)
    }

    // MARK: Sending

    @Test func aConfirmedMessageSendsTheThreeFieldsOnceAndClearsTheDraft() async {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let poster = ScriptedPoster([.success(newMessageConfirmed)])
        let model = composer(poster, drafts: drafts)
        await model.start()
        #expect(model.recipient == "user1")
        model.update(recipient: " user2 ")
        model.update(subject: " Rendez-vous ")
        model.update(text: "Bonjour\nà demain")
        await model.send()
        #expect(poster.calls == [
            .init(text: "Bonjour\nà demain", formURL: newMessageLink, recipient: "user2", subject: "Rendez-vous")
        ])
        #expect(model.closeReason == .sent(newMessageConfirmed))
        #expect(await drafts.draft(for: target.draftContext, account: ComposerFixture.account) == nil)
    }

    @Test func sendNeedsARecipientASubjectAndAText() async {
        let poster = ScriptedPoster([])
        let model = composer(poster)
        await model.start()
        model.update(text: "Bonjour")
        #expect(!model.canSend)
        model.update(subject: "Sujet")
        #expect(model.canSend)
        model.update(recipient: "  ")
        #expect(!model.canSend)
        await model.send()
        #expect(poster.calls.isEmpty)
    }

    @Test(arguments: ["recipient", "subject"])
    func aCharacterHFRWouldCutIsRefusedInEveryField(_ field: String) async {
        let poster = ScriptedPoster([.success(newMessageConfirmed)])
        let model = composer(poster)
        await model.start()
        model.update(subject: field == "subject" ? "Fête 🎉" : "Fête")
        model.update(recipient: field == "recipient" ? "user😀" : "user1")
        model.update(text: "Bonjour")
        await model.send()
        #expect(poster.calls.isEmpty)
        #expect(model.errorMessage?.contains(field == "subject" ? "🎉" : "😀") == true)
    }

    @Test func anUnconfirmedMessageSaysToCheckThePrivateMessages() async {
        let poster = ScriptedPoster([.failure(.unconfirmed(.transport(.timedOut)))])
        let model = composer(poster)
        await model.start()
        model.update(subject: "Sujet")
        model.update(text: "Bonjour")
        await model.send()
        #expect(model.mayHavePosted)
        #expect(model.errorMessage?.contains("messages privés") == true)
        await model.checkTopic()
        #expect(model.closeReason == .checkTopic)
        #expect(poster.calls.count == 1)
    }

    @Test func aRefusalNamesTheField() {
        #expect(ComposerMessages.message(for: .tooLong(.subject, maximum: 70), newMessage: true).contains("Le sujet dépasse 70"))
        #expect(ComposerMessages.message(for: .lineBreak(.recipient), newMessage: true).contains("Le destinataire"))
        #expect(ComposerMessages.message(for: .emptyInput(.recipient), newMessage: true).contains("destinataire"))
        #expect(ComposerMessages.message(for: .notLoggedIn, newMessage: true).hasSuffix("renvoyez le message."))
        #expect(!ComposerMessages.message(for: .tooLong(.subject, maximum: 70), newMessage: true).contains("peut-être"))
    }

    // MARK: Draft

    @Test func theSubjectAndTextAreKeptPerRecipientAndRestored() async {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let first = composer(ScriptedPoster([]), drafts: drafts)
        await first.start()
        first.update(subject: "Sujet gardé")
        #expect(first.closeNeedsChoice)
        first.update(text: "Texte gardé")
        first.update(recipient: "autre")
        await first.keepDraftAndClose()
        let stored = await drafts.draft(for: .privateMessage(recipient: "user1"), account: ComposerFixture.account)
        #expect(stored?.subject == "Sujet gardé")
        #expect(stored?.text == "Texte gardé")

        let second = composer(ScriptedPoster([]), drafts: drafts)
        await second.start()
        #expect(second.subject == "Sujet gardé")
        #expect(second.text == "Texte gardé")
        // The link's recipient, not the one typed: a draft keeps no recipient (LOT-063).
        #expect(second.recipient == "user1")
    }

    @Test func aReplyHasNoSubjectNorRecipient() async {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let model = ComposerFixture.model(poster: ScriptedPoster([]), drafts: drafts)
        await model.start()
        model.update(subject: "Sujet")
        model.update(recipient: "user1")
        #expect(!model.isNewMessage)
        #expect(model.subject.isEmpty)
        #expect(model.recipient.isEmpty)
        #expect(!model.closeNeedsChoice)
    }

    // MARK: Live poster

    @Test func theLivePosterRefusesALinkOffTheForumWithoutARequest() async {
        // `.invalid` never resolves: even without the engine's check, nothing could reach a server.
        let poster = LiveReplyPoster(session: HFRSession())
        await #expect(throws: PostingError.invalidFormURL) {
            try await poster.newPrivateMessage(
                to: "user1", subject: "Sujet", text: "texte", formURL: url("https://example.invalid/message.php?cat=prive")
            )
        }
    }
}
