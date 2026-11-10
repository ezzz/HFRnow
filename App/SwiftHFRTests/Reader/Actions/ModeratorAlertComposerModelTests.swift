import Foundation
import HFRClient
import HFRNetwork
@testable import SwiftHFR
import Testing

/// LOT-135: the reason sheet sends once, and HFR's answer decides whether it closes.
@MainActor
struct ModeratorAlertComposerModelTests {
    private final class Ended {
        var outcomes: [ModeratorAlertComposerModel.Outcome] = []
    }

    private func sheet(_ form: ScriptedAlertForm, ended: Ended = Ended(), reason: String = "Spam") -> ModeratorAlertComposerModel {
        let model = ModeratorAlertComposerModel(alert: form.prepared) { ended.outcomes.append($0) }
        model.reason = reason
        return model
    }

    @Test func envoyerNeedsAReasonThatIsNotBlank() async {
        let form = ScriptedAlertForm(.success("ok"))
        let model = sheet(form, reason: " \n\t")
        #expect(!model.canSend)
        await model.send()
        #expect(await form.reasons.isEmpty)
        model.reason = "Propos insultants"
        #expect(model.canSend)
    }

    @Test func hfrsConfirmationEndsTheSheetWithItsSentence() async {
        let ended = Ended()
        let form = ScriptedAlertForm(.success(" Un message a été envoyé avec succès aux modérateurs \n"))
        let model = sheet(form, ended: ended, reason: "Spam\nrépété")
        await model.send()
        #expect(ended.outcomes == [.sent("Un message a été envoyé avec succès aux modérateurs")])
        #expect(await form.reasons == ["Spam\nrépété"])
        #expect(!model.canSend)
    }

    @Test func aRefusalKeepsTheSheetAndTheReasonForAnotherTry() async {
        let refusals: [(ModeratorAlertError, String)] = [
            (.rejected(message: "Merci de patienter avant de poster à nouveau."), "Merci de patienter avant de poster à nouveau."),
            (.rejected(message: nil), "Le forum a refusé l’alerte : rien n’a été envoyé."),
            (.emptyReason, "Décrivez le problème avant d’envoyer."),
            (.unsupportedCharacters(["😀", "🚀"]),
             "Le forum ne peut pas enregistrer ces caractères : 😀 🚀. Retirez-les puis envoyez."),
            (.network(.cancelled), "Alerte annulée : rien n’a été envoyé.")
        ]
        for (error, text) in refusals {
            let ended = Ended()
            let form = ScriptedAlertForm(.failure(error), .success("ok"))
            let model = sheet(form, ended: ended)
            await model.send()
            #expect(ended.outcomes.isEmpty, "\(error)")
            #expect(model.error == text)
            #expect(model.reason == "Spam")
            #expect(model.canSend)
            await model.send()
            #expect(ended.outcomes == [.sent("ok")], "the second try goes through")
        }
    }

    @Test func anUnconfirmedAlertEndsTheSheetAndIsNeverSentAgain() async {
        let ended = Ended()
        let form = ScriptedAlertForm(.failure(.unconfirmed(.unrecognizedAnswer(message: "Réponse inattendue"))))
        let model = sheet(form, ended: ended)
        await model.send()
        #expect(ended.outcomes == [.unconfirmed(
            "Le forum n’a pas confirmé l’alerte : elle a peut-être été transmise aux modérateurs, elle n’est donc pas renvoyée."
                + " Réponse du forum : « Réponse inattendue »"
        )])
        #expect(!model.canSend)
        await model.send()
        #expect(await form.reasons.count == 1)
        let silent = Ended()
        await sheet(ScriptedAlertForm(.failure(.unconfirmed(.transport(.timedOut)))), ended: silent).send()
        #expect(silent.outcomes == [.unconfirmed(
            "Le forum n’a pas confirmé l’alerte : elle a peut-être été transmise aux modérateurs, elle n’est donc pas renvoyée."
        )])
    }

    @Test func aFormThatCannotBeSentAnyMoreEndsTheSheet() async {
        let cases: [(ModeratorAlertError, String)] = [
            (.notLoggedIn,
             "Votre session a expiré : rien n’a été envoyé. Reconnectez-vous depuis le menu Comptes, puis alertez à nouveau."),
            (.unsupportedForm(reason: "select"),
             "Le formulaire d’alerte du forum n’est pas pris en charge : rien n’a été envoyé. "
                + "Actualisez le sujet puis réessayez.")
        ]
        for (error, text) in cases {
            let ended = Ended()
            await sheet(ScriptedAlertForm(.failure(error)), ended: ended).send()
            #expect(ended.outcomes == [.closed(text)])
        }
    }

    @Test func aSecondTapWhileSendingSendsNothing() async {
        let ended = Ended()
        let form = ScriptedAlertForm(.success("ok"), holds: true)
        let model = sheet(form, ended: ended)
        let first = Task { await model.send() }
        #expect(await eventually { await form.isHolding })
        #expect(model.isSending)
        #expect(!model.canSend)
        let second = Task { await model.send() }
        // The second tap returns at once; if it were sending, it would be held too and `release` frees both.
        _ = await eventually { await form.reasons.count > 1 }
        await form.release()
        await second.value
        await first.value
        #expect(await form.reasons == ["Spam"])
        #expect(ended.outcomes == [.sent("ok")])
        #expect(!model.isSending)
    }
}
