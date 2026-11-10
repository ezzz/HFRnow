import Foundation
import HFRClient
import Observation

// Port of HFRswift/Swift/MessagesView.swift (openModerationAlertComposer `:4587-4609`, askAlertMailConfirmation and
// confirmAlertMailSending `:4568-4585`, the `.alert` entry `:2232-2254`) @ 87fe0d1c. Differences: GAP-070; the mail fallback
// needs an address injected at build time (Q-10) and its query is encoded strictly.
/// "Alerter" in the message menu (LOT-135): reads the message's alert page through the current account, says when HFR already
/// has an alert for it, opens the reason sheet, or, without an alert link, offers legacy's mail to the moderators.
@MainActor
@Observable
final class ModeratorAlertModel {
    /// A failure to show in an alert.
    struct Failure: Equatable, Identifiable {
        let id = UUID()
        let title: String
        let message: String
    }

    /// What is being read, as shown over the page; nil when nothing runs.
    private(set) var progress: String?
    /// The reason sheet on screen.
    var composer: ModeratorAlertComposerModel?
    /// The mail the user is asked to confirm (legacy "Alerter les modérateurs par email ?").
    var pendingMail: URL?
    /// What the alert says.
    var failure: Failure?

    private let alerter: (any ModeratorAlerting)?
    private let mailAddress: String?
    private let confirm: @MainActor (String) -> Void
    private let openMail: @MainActor (URL) -> Void

    /// Alerts through `alerter` (nil when no account is current) and, without an alert link, by mail to `mailAddress` (nil
    /// when the build carries none, Q-10). `confirm` shows HFR's sentence on the reader; `openMail` hands the mail to the system.
    init(
        alerter: (any ModeratorAlerting)?,
        mailAddress: String?,
        confirm: @escaping @MainActor (String) -> Void,
        openMail: @escaping @MainActor (URL) -> Void
    ) {
        self.alerter = alerter
        self.mailAddress = mailAddress.flatMap(ModeratorAlertMail.validAddress)
        self.confirm = confirm
        self.openMail = openMail
    }

    /// Nothing is being read, asked or composed: the model can be replaced by one with fresher services.
    var isIdle: Bool { progress == nil && composer == nil && pendingMail == nil && failure == nil }

    /// The menu entry; the policy already keeps it off the user's own messages.
    var handler: any MessageActionHandler {
        WriteActionHandler(
            kind: .alert,
            canRun: { [weak self] in self?.canAlert($0) ?? false },
            run: { [weak self] context in await self?.start(context) }
        )
    }

    /// Whether "Alerter" can run for `context`: an alert link with an account, or else the mail fallback.
    func canAlert(_ context: MessageMenuContext) -> Bool {
        guard !context.isOwnMessage else { return false }
        if context.actions.alertURL != nil, alerter != nil { return true }
        return mailURL(for: context) != nil
    }

    /// Legacy's order: the alert form when the message has a link (and an account), else the mail.
    func start(_ context: MessageMenuContext) async {
        guard !context.isOwnMessage else { return }
        if let link = context.actions.alertURL, let alerter {
            await prepare(link: link, with: alerter)
        } else if let mail = mailURL(for: context) {
            pendingMail = mail
        }
    }

    /// The user confirmed `mail`, the one the alert was shown for (SwiftUI clears `pendingMail` before the button's action
    /// runs, AGENTS.md LOT-087): the system opens it, the user sends it.
    func confirmMail(_ mail: URL) {
        pendingMail = nil
        openMail(mail)
    }

    private func mailURL(for context: MessageMenuContext) -> URL? {
        guard let mailAddress, let permalink = context.permalinkURL else { return nil }
        return ModeratorAlertMail.url(address: mailAddress, permalink: permalink)
    }

    /// One preparation at a time, never while a sheet is open (legacy `isPreparingModerationAlert`).
    private func prepare(link: URL, with alerter: any ModeratorAlerting) async {
        guard progress == nil, composer == nil else { return }
        progress = "Chargement de l’alerte…"
        defer { progress = nil }
        do throws(ModeratorAlertError) {
            switch try await alerter.prepare(link: link) {
            case .alreadyAlerted(let message):
                let sentence = message?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                confirm(sentence.isEmpty ? "Alerte déjà envoyée." : sentence)
            case .form(let alert):
                composer = ModeratorAlertComposerModel(alert: alert) { [weak self] outcome in self?.composerDidFinish(outcome) }
            }
        } catch {
            failure = Failure(title: "Alerte impossible", message: ModeratorAlertMessages.prepare(error))
        }
    }

    /// The sheet ended: it closes, and the reader says how.
    private func composerDidFinish(_ outcome: ModeratorAlertComposerModel.Outcome) {
        composer = nil
        switch outcome {
        case .sent(let sentence): confirm(sentence)
        case .closed(let message): failure = Failure(title: "Alerte impossible", message: message)
        case .unconfirmed(let message): failure = Failure(title: "Alerte non confirmée", message: message)
        }
    }
}

/// The mail fallback of legacy (`MessagesView.swift:4572-4585` @ 87fe0d1c): the user writes to the forum's moderation address,
/// which the build injects (Q-10, ADR 0007: a third party's address stays out of source).
enum ModeratorAlertMail {
    /// The Info.plist key holding the address (`App/Config/Info-Keys.plist`, from `MODERATOR_ALERT_MAIL_ADDRESS`).
    static let addressKey = "ModeratorAlertMailAddress"

    /// The address the build carries, nil when absent, blank, unexpanded or malformed.
    static func address(from info: [String: Any]) -> String? {
        (info[addressKey] as? String).flatMap(validAddress)
    }

    /// `address` trimmed when it is one `local@domain` token without spaces or URL delimiters, else nil.
    static func validAddress(_ address: String) -> String? {
        let trimmed = address.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, parts.allSatisfy({ !$0.isEmpty }), parts[1].contains("."), !trimmed.hasPrefix("$("),
              trimmed.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return trimmed
    }

    /// `mailto:<address>` with legacy's subject and body (`Message : <permalink>`), every query character outside RFC 3986's
    /// unreserved set percent-encoded (legacy's `.urlQueryAllowed` left a `&` of the permalink as is, cutting the body).
    static func url(address: String, permalink: URL) -> URL? {
        guard let address = validAddress(address) else { return nil }
        let subject = encode("[HardWare.fr] Signalement d'un contenu illicite")
        let body = encode("Message : \(permalink.absoluteString)")
        return URL(string: "mailto:\(address)?subject=\(subject)&body=\(body)")
    }

    private static func encode(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: unreserved) ?? ""
    }

    private static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    private static let allowed = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._+@")
}
