import Foundation
import HFRClient
import HFRNetwork

// Port of HFRswift/Swift/ReplyService.swift (ForumModerationAlertService, `:1437-1540`) @ 87fe0d1c, through LOT-050's
// `ModeratorAlertFlow`. Differences: GAP-070; success only on HFR's confirmation, `unconfirmed` never resent (LOT-050).

/// What HFR serves at a message's alert link, as the alert screen uses it (LOT-135).
enum ModeratorAlertPreparation: Sendable {
    /// HFR says the message was already reported; `message` is its sentence, nil when it gave none.
    case alreadyAlerted(message: String?)
    /// The alert form, ready to be sent once.
    case form(PreparedModeratorAlert)
}

/// The alert form of one message, read through the current account's session: `send` posts it with a reason and returns
/// HFR's confirmation sentence (`W46`). A closure, so the screen's tests script it without a session or a request.
struct PreparedModeratorAlert: Sendable {
    let send: @Sendable (String) async throws(ModeratorAlertError) -> String
}

/// Reads a message's alert page; an app-side seam over `ModeratorAlertFlow` for the screen's tests.
protocol ModeratorAlerting: Sendable {
    /// Reads the alert page at `link` (LOT-031's `alertURL`) through the account's session.
    func prepare(link: URL) async throws(ModeratorAlertError) -> ModeratorAlertPreparation
}

/// The current account's alerts, through LOT-050's flow and the account's session (`AppEnvironment`, built only when an
/// account is current).
struct LiveModeratorAlerter: ModeratorAlerting {
    let session: HFRSession

    func prepare(link: URL) async throws(ModeratorAlertError) -> ModeratorAlertPreparation {
        let flow = ModeratorAlertFlow()
        switch try await flow.prepare(link: link, in: session) {
        case .alreadyAlerted(let message):
            return .alreadyAlerted(message: message)
        case .form(let form):
            return .form(PreparedModeratorAlert { reason async throws(ModeratorAlertError) -> String in
                try await flow.submit(reason: reason, with: form).message
            })
        }
    }
}
