import Foundation
import HFRClient
import Observation

// Port of HFRswift/Swift/MessagesView.swift (ModerationAlertComposerView: `canSend`, `submitAlert`, `:7415-7524`) @ 87fe0d1c.
// Differences: GAP-070; only HFR's confirmation is a success, and an alert HFR did not confirm closes the sheet instead of
// staying ready to send again.
/// The reason sheet of one alert (LOT-135): one send at a time, HFR's answer decides whether the sheet closes.
@MainActor
@Observable
final class ModeratorAlertComposerModel: Identifiable {
    /// How the sheet ended.
    enum Outcome: Equatable {
        /// HFR confirmed; its sentence.
        case sent(String)
        /// Nothing was sent and this form cannot be sent any more; why.
        case closed(String)
        /// The alert may have reached the moderators; it is not sent again.
        case unconfirmed(String)
    }

    /// Legacy's warning, above the reason (`MessagesView.swift:7427-7428` @ 87fe0d1c).
    static let warning =
        "Attention : le message que vous écrivez ici sera envoyé directement aux modérateurs via message privé ou e-mail."

    /// The reason typed by the user.
    var reason = ""
    /// Why the last send failed while the sheet stays open; the view clears it.
    var error: String?
    /// A send is running: "Annuler", the swipe-down and "Envoyer" wait for it.
    private(set) var isSending = false
    /// The sheet ended (sent, closed or unconfirmed): nothing more is sent from it, even by a late tap.
    private(set) var isFinished = false

    private let alert: PreparedModeratorAlert
    private let finish: @MainActor (Outcome) -> Void

    /// The sheet of `alert`; `finish` closes it and tells the reader.
    init(alert: PreparedModeratorAlert, finish: @escaping @MainActor (Outcome) -> Void) {
        self.alert = alert
        self.finish = finish
    }

    /// "Envoyer" is enabled for a non-blank reason when nothing is being sent (legacy `canSend`).
    var canSend: Bool {
        !isSending && !isFinished && !reason.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Sends the reason once. HFR's confirmation closes the sheet; a refusal keeps it with the reason; an alert that may have
    /// left closes it and is never offered again.
    func send() async {
        guard canSend else { return }
        isSending = true
        defer { isSending = false }
        do throws(ModeratorAlertError) {
            let sentence = try await alert.send(reason).trimmingCharacters(in: .whitespacesAndNewlines)
            end(.sent(sentence.isEmpty ? "Alerte envoyée." : sentence))
        } catch {
            switch ModeratorAlertMessages.submit(error) {
            case .keep(let message): self.error = message
            case .close(let message): end(.closed(message))
            case .unconfirmed(let message): end(.unconfirmed(message))
            }
        }
    }

    private func end(_ outcome: Outcome) {
        isFinished = true
        finish(outcome)
    }
}
