import Foundation
import HFRClient
import HFRModels
import HFRNetwork
import HFRStorage
@testable import SwiftHFR
import Testing

/// The new-topic link of a forum's topic list (`R05a`: `#md_btn_new_topic`, a category path).
let newTopicPath = "/hfr/Discussions/nouveau_sujet.htm"

/// The target of `newTopicPath` in forum 13.
let newTopicTarget: NewTopicTarget = {
    guard let target = NewTopicTarget(path: newTopicPath, forum: .forum(13)) else { preconditionFailure("R05a's link is a target") }
    return target
}()

/// The sub-categories of `R45a` (HFR-PROTOCOL §6c: 16 options, the first `value=""` "Aucune", none selected); three suffice here.
let newTopicOptions = NewTopicOptions(
    subcategories: [
        FormOption(value: "", label: "Aucune"), FormOption(value: "1", label: "Actualité"), FormOption(value: "2", label: "Politique")
    ],
    preselected: ""
)

/// HFR's confirmation of a new topic: the sentence of `W10`/HFR-PROTOCOL §7 E15 (a public new-topic answer is pending capture).
let newTopicConfirmed = PostingResult(
    action: .newTopic, message: "Votre message a été posté avec succès !",
    refreshURL: url("https://forum.hardware.fr/forum1.php?config=hfr.inc&cat=13&page=1&subcat=0&sondage=0&owntopic=0")
)

/// The new topic composer (LOT-089): subject, sub-category and text, its draft, and what it sends.
@MainActor
struct NewTopicComposerTests {
    private func composer(
        _ poster: ScriptedPoster, drafts: DraftStore = DraftStore(persistence: InMemoryDraftPersistence())
    ) -> ReplyComposerModel {
        ReplyComposerModel(
            composing: .newTopic(newTopicTarget), services: ComposerFixture.services(poster: poster, drafts: drafts),
            autosaveDelay: .seconds(60)
        )
    }

    private func scripted(_ outcomes: [Result<PostingResult, PostingError>] = []) -> ScriptedPoster {
        let poster = ScriptedPoster(outcomes)
        poster.scriptOptions([.success(newTopicOptions)])
        return poster
    }

    // MARK: Target

    @Test func theListLinkIsTheComposerAndTheForumKeysTheDraft() {
        #expect(newTopicTarget.formURL == url("https://forum.hardware.fr/hfr/Discussions/nouveau_sujet.htm"))
        #expect(newTopicTarget.draftContext == .newTopic(forum: .forum(13)))
    }

    @Test(arguments: [nil, "https://example.invalid/hfr/Discussions/nouveau_sujet.htm", "http://forum.hardware.fr/hfr/x/nouveau_sujet.htm"])
    func aLinkOffTheForumOrMissingIsNoTarget(_ path: String?) {
        #expect(NewTopicTarget(path: path, forum: .forum(13)) == nil)
    }

    @Test func noCategoryOrThePrivateMessagesGivesNoTarget() {
        #expect(NewTopicTarget(path: newTopicPath, forum: nil) == nil)
        #expect(NewTopicTarget(path: "/message.php?config=hfr.inc&cat=prive&dest=", forum: .privateMessages) == nil)
    }

    // MARK: Sub-categories

    @Test func theFormsOptionsAreReadAndItsPreselectionHonoured() async {
        let poster = scripted()
        let model = composer(poster)
        await model.start()
        await model.loadSubcategories()
        #expect(model.picker.options.map(\.label) == ["Aucune", "Actualité", "Politique"])
        #expect(model.picker.selected == "")
        #expect(poster.optionRequests == [newTopicTarget.formURL])
        let preselected = NewTopicOptions(subcategories: newTopicOptions.subcategories, preselected: "2")
        let other = ScriptedPoster([])
        other.scriptOptions([.success(preselected)])
        let second = composer(other)
        await second.start()
        await second.loadSubcategories()
        #expect(second.picker.selected == "2")
    }

    @Test func aChoiceIsSentAndOnlyAnOfferedOneCanBeChosen() async {
        let poster = scripted([.success(newTopicConfirmed)])
        let model = composer(poster)
        await model.start()
        await model.loadSubcategories()
        model.select(subcategory: "1")
        model.select(subcategory: "99")
        #expect(model.picker.selected == "1")
        model.update(subject: "Mon sujet")
        model.update(text: "Bonjour")
        await model.send()
        #expect(poster.calls == [.init(text: "Bonjour", formURL: newTopicTarget.formURL, subject: "Mon sujet", subcategory: "1")])
    }

    @Test func aFailedReadWarnsLetsSendAndRetryReadsTheOptions() async {
        let poster = ScriptedPoster([.success(newTopicConfirmed)])
        poster.scriptOptions([.failure(.network(.offline)), .success(newTopicOptions)])
        let model = composer(poster)
        await model.start()
        await model.loadSubcategories()
        #expect(model.picker.options.isEmpty)
        #expect(model.picker.warning?.contains("sous-catégories") == true)
        model.update(subject: "Sujet")
        model.update(text: "Texte")
        #expect(model.canSend)
        await model.loadSubcategories()
        #expect(model.picker.warning == nil)
        #expect(model.picker.selected == "")
        await model.send()
        // The form was read twice for the options (fail, retry), the write reads it again itself.
        #expect(poster.optionRequests.count == 2)
        #expect(poster.calls.first?.subcategory == "")
    }

    @Test func aChoiceHFRNoLongerOffersIsReadAgainAndNothingIsResent() async {
        let poster = ScriptedPoster([.failure(.unknownSubcategory)])
        let changed = NewTopicOptions(subcategories: [FormOption(value: "", label: "Aucune")], preselected: "")
        poster.scriptOptions([.success(newTopicOptions), .success(changed)])
        let model = composer(poster)
        await model.start()
        await model.loadSubcategories()
        model.select(subcategory: "2")
        model.update(subject: "Sujet")
        model.update(text: "Texte")
        await model.send()
        #expect(model.errorMessage?.contains("choisissez-la à nouveau") == true)
        #expect(model.picker.options.count == 1)
        #expect(model.picker.selected == "")
        #expect(poster.optionRequests.count == 2)
        #expect(poster.calls.count == 1)
        #expect(!model.mayHavePosted)
    }

    // MARK: Sending

    @Test func aConfirmedTopicClearsTheDraftAndClosesAsSent() async {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let poster = scripted([.success(newTopicConfirmed)])
        let model = composer(poster, drafts: drafts)
        await model.start()
        model.update(subject: " Mon sujet ")
        model.update(text: "Bonjour\nle forum")
        await model.send()
        #expect(poster.calls == [
            .init(text: "Bonjour\nle forum", formURL: newTopicTarget.formURL, subject: "Mon sujet", subcategory: nil)
        ])
        #expect(model.closeReason == .sent(newTopicConfirmed))
        #expect(await drafts.draft(for: newTopicTarget.draftContext, account: ComposerFixture.account) == nil)
    }

    @Test func sendNeedsASubjectAndATextButNoRecipient() async {
        let poster = scripted()
        let model = composer(poster)
        await model.start()
        #expect(!model.isNewMessage)
        model.update(text: "Bonjour")
        #expect(!model.canSend)
        model.update(subject: "   ")
        #expect(!model.canSend)
        model.update(subject: "Sujet")
        #expect(model.canSend)
        model.update(recipient: "ignoré")
        #expect(model.recipient.isEmpty)
        await model.send()
        #expect(poster.calls.count == 1)
    }

    @Test func aCharacterHFRWouldCutIsRefusedInTheSubject() async {
        let poster = scripted([.success(newTopicConfirmed)])
        let model = composer(poster)
        await model.start()
        model.update(subject: "Fête 🎉")
        model.update(text: "Bonjour")
        await model.send()
        #expect(poster.calls.isEmpty)
        #expect(model.errorMessage?.contains("🎉") == true)
    }

    @Test func anUnconfirmedTopicSaysToCheckTheListAndNeverResends() async {
        let poster = scripted([.failure(.unconfirmed(.transport(.timedOut)))])
        let model = composer(poster)
        await model.start()
        model.update(subject: "Sujet")
        model.update(text: "Bonjour")
        await model.send()
        #expect(model.mayHavePosted)
        #expect(model.errorMessage?.contains("liste des sujets") == true)
        await model.checkTopic()
        #expect(model.closeReason == .checkTopic)
        #expect(poster.calls.count == 1)
    }

    @Test func refusalsSpeakOfTheTopic() {
        #expect(ComposerMessages.message(for: .tooLong(.subject, maximum: 70), newTopic: true).contains("Le sujet dépasse 70"))
        #expect(ComposerMessages.message(for: .notLoggedIn, newTopic: true).hasSuffix("renvoyez le sujet."))
        #expect(ComposerMessages.message(for: .formUnavailable(message: nil), newTopic: true).contains("créer un sujet"))
        #expect(ComposerMessages.message(for: .rejected(message: "Flood"), newTopic: true) == "Flood")
        #expect(!ComposerMessages.message(for: .tooLong(.subject, maximum: 70), newTopic: true).contains("peut-être"))
    }

    // MARK: Draft

    @Test func theSubjectAndTextAreKeptPerForumAndRestored() async {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let first = composer(scripted(), drafts: drafts)
        await first.start()
        first.update(subject: "Sujet gardé")
        #expect(first.closeNeedsChoice)
        first.update(text: "Texte gardé")
        await first.keepDraftAndClose()
        #expect(first.closeReason == .keptDraft)
        let again = composer(scripted(), drafts: drafts)
        await again.start()
        #expect(again.subject == "Sujet gardé")
        #expect(again.text == "Texte gardé")
        // Another forum has its own draft.
        let elsewhere = ReplyComposerModel(
            composing: .newTopic(NewTopicTarget(path: "/hfr/Hardware/nouveau_sujet.htm", forum: .forum(1)) ?? newTopicTarget),
            services: ComposerFixture.services(poster: scripted(), drafts: drafts), autosaveDelay: .seconds(60)
        )
        await elsewhere.start()
        #expect(elsewhere.subject.isEmpty)
    }

    @Test func aSubjectAloneIsADraftAndDiscardingRemovesIt() async {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let model = composer(scripted(), drafts: drafts)
        await model.start()
        model.update(subject: "Seulement un sujet")
        await model.flushDraft()
        #expect(await drafts.draft(for: newTopicTarget.draftContext, account: ComposerFixture.account)?.subject == "Seulement un sujet")
        await model.discardDraftAndClose()
        #expect(await drafts.draft(for: newTopicTarget.draftContext, account: ComposerFixture.account) == nil)
    }
}
