import Foundation
import HFRClient
import HFRNetwork
@testable import SwiftHFR
import Testing

/// LOT-135: "Alerter" in the message menu, from the alert link to the sheet, and the mail fallback.
@MainActor
struct ModeratorAlertModelTests {
    private static let permalink = url("https://forum.hardware.fr/forum2.php?config=hfr.inc&cat=13&post=28563&page=1#t2666649")

    private final class Told {
        var confirmations: [String] = []
        var mails: [URL] = []
    }

    private func model(_ alerter: ScriptedAlerter?, mail: String? = nil, told: Told = Told()) -> ModeratorAlertModel {
        ModeratorAlertModel(
            alerter: alerter, mailAddress: mail, confirm: { told.confirmations.append($0) }, openMail: { told.mails.append($0) }
        )
    }

    private func form(_ answer: Result<String, ModeratorAlertError>) -> ScriptedAlertForm {
        ScriptedAlertForm(answer)
    }

    // MARK: Entry

    @Test func theEntryNeedsAnAlertLinkWithAnAccountOrTheConfiguredMail() {
        let alerter = ScriptedAlerter(.success(.alreadyAlerted(message: nil)))
        #expect(model(alerter).canAlert(alertContext()))
        #expect(!model(nil).canAlert(alertContext(permalink: Self.permalink)), "no account, no mail")
        #expect(model(nil, mail: moderationAddress).canAlert(alertContext(permalink: Self.permalink)), "no account: the mail")
        #expect(model(alerter, mail: moderationAddress).canAlert(alertContext(alert: nil, permalink: Self.permalink)))
        #expect(!model(alerter).canAlert(alertContext(alert: nil, permalink: Self.permalink)), "no link and no address")
        #expect(!model(alerter, mail: moderationAddress).canAlert(alertContext(alert: nil)), "no permalink to mail")
        #expect(!model(alerter, mail: moderationAddress).canAlert(alertContext(permalink: Self.permalink, own: true)))
    }

    @Test func theRegisteredHandlerServesAlerterOnlyWhereItCanRun() async {
        let alerter = ScriptedAlerter(.success(.alreadyAlerted(message: "déjà")))
        let told = Told()
        let alerts = model(alerter, told: told)
        let registry = MessageActionRegistry([alerts.handler])
        #expect(registry.entries(for: alertContext(), source: .message) == [.alert])
        #expect(registry.entries(for: alertContext(alert: nil, permalink: Self.permalink), source: .message).isEmpty)
        #expect(await registry.perform(.alert, with: alertContext()))
        #expect(await alerter.links == [alertLink])
        #expect(told.confirmations == ["déjà"])
    }

    // MARK: Prepare

    @Test func alreadyAlertedShowsHFRsSentenceOrLegacysText() async {
        let told = Told()
        let sentence = "Votre demande de modération sur ce message n'est pas encore traitée."
        let alerter = ScriptedAlerter(.success(.alreadyAlerted(message: " \(sentence)\n")))
        let alerts = model(alerter, told: told)
        await alerts.start(alertContext())
        #expect(told.confirmations == [sentence])
        #expect(alerts.composer == nil)
        #expect(alerts.progress == nil)
        await model(ScriptedAlerter(.success(.alreadyAlerted(message: nil))), told: told).start(alertContext())
        #expect(told.confirmations.last == "Alerte déjà envoyée.")
    }

    @Test func theFormOpensTheSheetAndNothingIsSent() async {
        let sheet = form(.success("ok"))
        let alerter = ScriptedAlerter(.success(.form(sheet.prepared)))
        let alerts = model(alerter)
        #expect(alerts.isIdle)
        await alerts.start(alertContext())
        #expect(alerts.composer != nil)
        #expect(!alerts.isIdle, "a reinstall of the menu keeps this model while its sheet is open")
        #expect(await sheet.reasons.isEmpty)
    }

    @Test func oneAlertIsPreparedAtATimeAndNoneWhileTheSheetIsOpen() async {
        let alerter = ScriptedAlerter(.success(.form(form(.success("ok")).prepared)), holds: true)
        let alerts = model(alerter)
        let first = Task { await alerts.start(alertContext()) }
        #expect(await eventually { await alerter.isHolding })
        #expect(alerts.progress == "Chargement de l’alerte…")
        let second = Task { await alerts.start(alertContext()) }
        _ = await eventually { await alerter.links.count > 1 } // a second prepare would be held too: `release` frees both
        await alerter.release()
        await second.value
        await first.value
        #expect(await alerter.links.count == 1, "a second tap while preparing")
        #expect(alerts.composer != nil)
        let third = Task { await alerts.start(alertContext()) }
        _ = await eventually { await alerter.links.count > 1 }
        await alerter.release()
        await third.value
        #expect(await alerter.links.count == 1, "a tap while the sheet is open")
    }

    @Test func aFailedPreparationSaysWhyAndThatNothingWasSent() async {
        let cases: [(ModeratorAlertError, String)] = [
            (.formUnavailable(message: "Sujet verrouillé."), "Sujet verrouillé."),
            (.formUnavailable(message: nil),
             "Le forum ne propose pas d’alerter les modérateurs sur ce message. Rien n’a été envoyé."),
            (.notLoggedIn,
             "Votre session a expiré : rien n’a été envoyé. Reconnectez-vous depuis le menu Comptes, puis alertez à nouveau."),
            (.invalidLink, "Le lien d’alerte de ce message ne mène pas au forum : rien n’a été envoyé."),
            (.network(.offline), "Pas de connexion à internet : rien n’a été envoyé. Réessayez une fois connecté.")
        ]
        for (error, text) in cases {
            let alerts = model(ScriptedAlerter(.failure(error)))
            await alerts.start(alertContext())
            #expect(alerts.failure?.title == "Alerte impossible")
            #expect(alerts.failure?.message == text)
            #expect(alerts.composer == nil)
        }
    }

    // MARK: Sheet outcome

    @Test func aConfirmedAlertClosesTheSheetWithHFRsSentence() async throws {
        let told = Told()
        let sheet = form(.success("Un message a été envoyé avec succès aux modérateurs"))
        let alerts = model(ScriptedAlerter(.success(.form(sheet.prepared))), told: told)
        await alerts.start(alertContext())
        let composer = try #require(alerts.composer)
        composer.reason = "Spam"
        await composer.send()
        #expect(alerts.composer == nil)
        #expect(told.confirmations == ["Un message a été envoyé avec succès aux modérateurs"])
        #expect(await sheet.reasons == ["Spam"])
    }

    @Test func anUnconfirmedAlertClosesTheSheetAndIsNotOfferedAgain() async throws {
        let told = Told()
        let sheet = form(.failure(.unconfirmed(.transport(.timedOut))))
        let alerts = model(ScriptedAlerter(.success(.form(sheet.prepared))), told: told)
        await alerts.start(alertContext())
        let composer = try #require(alerts.composer)
        composer.reason = "Spam"
        await composer.send()
        #expect(alerts.composer == nil)
        #expect(alerts.failure?.title == "Alerte non confirmée")
        #expect(told.confirmations.isEmpty)
        await composer.send() // a late tap on the closing sheet
        #expect(await sheet.reasons == ["Spam"], "sent once, never again")
    }

    @Test func aFormThatCannotBeSentAnyMoreClosesTheSheet() async throws {
        let sheet = form(.failure(.sessionChanged))
        let alerts = model(ScriptedAlerter(.success(.form(sheet.prepared))))
        await alerts.start(alertContext())
        let composer = try #require(alerts.composer)
        composer.reason = "Spam"
        await composer.send()
        #expect(alerts.composer == nil)
        #expect(alerts.failure?.title == "Alerte impossible")
        #expect(alerts.failure?.message
            == "Le compte connecté a changé depuis l’ouverture de l’alerte : rien n’a été envoyé. Alertez à nouveau.")
    }

    // MARK: Mail fallback

    @Test func withoutAnAlertLinkTheConfiguredMailIsAskedThenOpened() async throws {
        let told = Told()
        let alerter = ScriptedAlerter(.success(.alreadyAlerted(message: nil)))
        let alerts = model(alerter, mail: " \(moderationAddress) ", told: told)
        await alerts.start(alertContext(alert: nil, permalink: Self.permalink))
        let mail = try #require(alerts.pendingMail)
        #expect(mail.absoluteString == "mailto:moderation@example.org"
            + "?subject=%5BHardWare.fr%5D%20Signalement%20d%27un%20contenu%20illicite"
            + "&body=Message%20%3A%20https%3A%2F%2Fforum.hardware.fr%2Fforum2.php%3Fconfig%3Dhfr.inc%26cat%3D13%26post%3D28563"
            + "%26page%3D1%23t2666649")
        #expect(await alerter.links.isEmpty)
        #expect(told.mails.isEmpty, "nothing opens before the user says yes")
        alerts.pendingMail = nil // SwiftUI clears the presenting state before the button's action
        alerts.confirmMail(mail)
        #expect(told.mails == [mail])
    }

    @Test func withAnAccountTheAlertLinkWinsOverTheMail() async {
        let alerter = ScriptedAlerter(.success(.alreadyAlerted(message: nil)))
        let told = Told()
        let alerts = model(alerter, mail: moderationAddress, told: told)
        await alerts.start(alertContext(permalink: Self.permalink))
        #expect(await alerter.links == [alertLink])
        #expect(alerts.pendingMail == nil)
        #expect(told.mails.isEmpty)
    }

    @Test func aPendingMailOrAShownFailureKeepsTheModelAcrossAReinstall() async {
        let mail = model(nil, mail: moderationAddress)
        await mail.start(alertContext(alert: nil, permalink: Self.permalink))
        #expect(!mail.isIdle)
        let failed = model(ScriptedAlerter(.failure(.notLoggedIn)))
        await failed.start(alertContext())
        #expect(!failed.isIdle)
        failed.failure = nil
        #expect(failed.isIdle)
    }

    @Test func noAccountWithAnAlertLinkFallsBackToTheMail() async {
        let alerts = model(nil, mail: moderationAddress)
        await alerts.start(alertContext(permalink: Self.permalink))
        #expect(alerts.pendingMail?.scheme == "mailto")
    }

    @Test func theBuildSettingDecidesWhetherAMessageWithoutAnAlertLinkOffersTheMail() {
        let context = alertContext(alert: nil, permalink: Self.permalink)
        let withSetting = ModeratorAlertMail.address(from: [ModeratorAlertMail.addressKey: moderationAddress])
        #expect(model(nil, mail: withSetting).canAlert(context), "setting present: the mail fallback is offered")
        #expect(model(ScriptedAlerter(.success(.alreadyAlerted(message: nil))), mail: withSetting).canAlert(context))
        let without = ModeratorAlertMail.address(from: [ModeratorAlertMail.addressKey: ""])
        #expect(!model(nil, mail: without).canAlert(context), "setting empty: no fallback")
        #expect(!model(nil, mail: ModeratorAlertMail.address(from: [:])).canAlert(context), "key absent: no fallback")
    }

    @Test func onlyOneWellFormedAddressIsAccepted() {
        for bad in ["", "  ", "$(MODERATOR_ALERT_MAIL_ADDRESS)", "a b@example.org", "moderation@example", "a@@example.org",
                    "@example.org", "moderation@", "moderation@example.org?cc=x@example.org", "a@example.org&bcc=b@example.org",
                    "moderation@example.org,b@example.org", "mailto:moderation@example.org"] {
            #expect(ModeratorAlertMail.validAddress(bad) == nil, "\(bad)")
            #expect(!model(nil, mail: bad).canAlert(alertContext(alert: nil, permalink: Self.permalink)), "\(bad)")
        }
        #expect(ModeratorAlertMail.validAddress(" moderation@example.org\n") == moderationAddress)
        #expect(ModeratorAlertMail.address(from: [ModeratorAlertMail.addressKey: moderationAddress]) == moderationAddress)
        #expect(ModeratorAlertMail.address(from: [ModeratorAlertMail.addressKey: "$(MODERATOR_ALERT_MAIL_ADDRESS)"]) == nil)
        #expect(ModeratorAlertMail.address(from: [:]) == nil)
    }
}
