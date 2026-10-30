import Foundation
import HFRClient
import HFRModels
import HFRStorage
@testable import SwiftHFR
import Testing

/// Sending a reply: success only on HFR's confirmation, the text and its draft kept on every other outcome, non-BMP
/// characters refused before anything is sent, one send at a time.
@MainActor
struct ReplyComposerSendTests {
    @Test func aConfirmedReplyIsSentOnceThroughTheTopicFormAndClearsTheDraft() async {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let poster = ScriptedPoster([.success(replyConfirmed)])
        let composer = ComposerFixture.model(poster: poster, drafts: drafts)
        await composer.start()
        composer.update(text: "Bonjour\nà tous")
        await composer.send()
        #expect(poster.calls == [ScriptedPoster.Call(text: "Bonjour\nà tous", formURL: replyFormURL)])
        #expect(composer.closeReason == .sent(replyConfirmed))
        #expect(composer.errorMessage == nil)
        #expect(await ComposerFixture.storedText(drafts) == nil)
    }

    @Test(arguments: [
        PostingError.rejected(message: "Vous devez remplir tous les champs avant de poster ce message"),
        .rejected(message: nil),
        .notLoggedIn,
        .formUnavailable(message: "Ce sujet est fermé"),
        .formUnavailable(message: nil),
        .network(.offline),
        .network(.timedOut),
        .network(.httpStatus(code: 503, url: replyFormURL)),
        .invalidFormURL,
        .formMismatch(expected: .reply, actual: .edit),
        .unconfirmed(.transport(.timedOut)),
        .unconfirmed(.unrecognizedAnswer(message: nil)),
        .unconfirmed(.unexpectedConfirmation(message: "Votre message a été édité avec succès !"))
    ])
    func everyOtherOutcomeKeepsTheTextAndTheDraftAndSaysWhatHappened(_ failure: PostingError) async {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let poster = ScriptedPoster([.failure(failure)])
        let composer = ComposerFixture.model(poster: poster, drafts: drafts)
        await composer.start()
        composer.update(text: "Ma réponse")
        await composer.send()
        #expect(composer.closeReason == nil)
        #expect(composer.text == "Ma réponse")
        #expect(composer.errorMessage == ComposerMessages.message(for: failure))
        #expect(composer.canSend)
        #expect(await ComposerFixture.storedText(drafts) == "Ma réponse")
        if case .unconfirmed = failure {
            #expect(composer.mayHavePosted)
        } else {
            #expect(!composer.mayHavePosted)
        }
    }

    @Test func charactersOutsideTheBMPAreRefusedBeforeAnythingIsSent() async {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let poster = ScriptedPoster([.success(replyConfirmed)])
        let composer = ComposerFixture.model(poster: poster, drafts: drafts)
        await composer.start()
        composer.update(text: "avant 😀 après 😀 ❤ é 🇫🇷")
        await composer.send()
        #expect(poster.calls.isEmpty)
        #expect(composer.closeReason == nil)
        #expect(composer.errorMessage == ComposerMessages.unsupported(["😀", "🇫🇷"]))
        #expect(composer.text == "avant 😀 après 😀 ❤ é 🇫🇷")
    }

    @Test func bmpCharactersAreSent() async {
        let poster = ScriptedPoster([.success(replyConfirmed)])
        let composer = ComposerFixture.model(poster: poster)
        await composer.start()
        composer.update(text: "☺ ❤ é ü ß")
        await composer.send()
        #expect(poster.calls.map(\.text) == ["☺ ❤ é ü ß"])
    }

    @Test func blankTextCannotBeSent() async {
        let poster = ScriptedPoster([.success(replyConfirmed)])
        let composer = ComposerFixture.model(poster: poster)
        await composer.start()
        composer.update(text: " \n\t ")
        #expect(!composer.canSend)
        await composer.send()
        #expect(poster.calls.isEmpty)
    }

    @Test func aSecondSendWhileOneRunsSendsNothingAndTypingIsIgnored() async {
        let gate = ReaderGate()
        let poster = ScriptedPoster([.success(replyConfirmed), .success(replyConfirmed)], gate: gate)
        let composer = ComposerFixture.model(poster: poster)
        await composer.start()
        composer.update(text: "Une fois")
        let first = Task { await composer.send() }
        await gate.untilArrived()
        #expect(composer.isSending)
        #expect(!composer.canSend)
        await composer.send()
        composer.update(text: "Une fois, modifié")
        await composer.requestClose()
        await gate.open()
        await first.value
        #expect(poster.calls.count == 1)
        #expect(composer.closeReason == .sent(replyConfirmed))
    }

    @Test func theDraftHoldsTheExactTextBeforeTheRequestLeaves() async {
        let gate = ReaderGate()
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let poster = ScriptedPoster([.success(replyConfirmed)], gate: gate)
        let composer = ComposerFixture.model(poster: poster, drafts: drafts)
        await composer.start()
        composer.update(text: "Texte envoyé")
        let send = Task { await composer.send() }
        await gate.untilArrived()
        #expect(await ComposerFixture.storedText(drafts) == "Texte envoyé")
        await gate.open()
        await send.value
        #expect(await ComposerFixture.storedText(drafts) == nil)
    }

    @Test func aPendingAutosaveNeverBringsTheDraftBackAfterAConfirmedSend() async throws {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let poster = ScriptedPoster([.success(replyConfirmed)])
        let composer = ComposerFixture.model(poster: poster, drafts: drafts, autosaveDelay: .milliseconds(20))
        await composer.start()
        composer.update(text: "Envoyé vite")
        await composer.send()
        try await Task.sleep(for: .milliseconds(100))
        #expect(await ComposerFixture.storedText(drafts) == nil)
    }

    @Test func checkingTheTopicIsOfferedOnlyAfterAnUnconfirmedSendAndKeepsTheDraft() async {
        let drafts = DraftStore(persistence: InMemoryDraftPersistence())
        let poster = ScriptedPoster([.failure(.rejected(message: nil)), .failure(.unconfirmed(.transport(.timedOut)))])
        let composer = ComposerFixture.model(poster: poster, drafts: drafts)
        await composer.start()
        composer.update(text: "Peut-être postée")
        await composer.send()
        await composer.checkTopic()
        #expect(composer.closeReason == nil)
        await composer.send()
        await composer.checkTopic()
        #expect(composer.closeReason == .checkTopic)
        #expect(await ComposerFixture.storedText(drafts) == "Peut-être postée")
        #expect(poster.calls.count == 2)
    }

    @Test func typingAfterAFailureClearsTheMessage() async {
        let poster = ScriptedPoster([.failure(.unconfirmed(.transport(.timedOut)))])
        let composer = ComposerFixture.model(poster: poster)
        await composer.start()
        composer.update(text: "Un")
        await composer.send()
        #expect(composer.mayHavePosted)
        composer.update(text: "Un deux")
        #expect(composer.errorMessage == nil)
        #expect(!composer.mayHavePosted)
    }
}
