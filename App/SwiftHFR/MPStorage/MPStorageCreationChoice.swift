import Observation

/// The creation question as a choice (#1014): « Oui » is preselected, and « Non » is only recorded after a confirmation that says
/// what is lost. Pure state, so the rule is tested without a view; nothing here creates anything: the caller creates the
/// storage message only for `.create`, which only « Oui » yields.
@MainActor
@Observable
final class MPStorageCreationChoice {
    /// The two answers of the question.
    enum Answer: String, CaseIterable, Identifiable {
        case oui
        case non

        var id: Self { self }

        /// The choice's label.
        var label: String { self == .oui ? "Oui" : "Non" }
    }

    /// What the member decided once nothing is left to confirm.
    enum Decision: Equatable {
        /// « Oui »: create the storage message.
        case create
        /// « Non », confirmed: record the refusal for this account; nothing is created.
        case decline
    }

    /// The selected answer: « Oui » at first.
    var answer = Answer.oui
    /// True while the confirmation of a « Non » waits for its answer (« Confirmer » or « Revenir »).
    var asksRefusalConfirmation = false

    /// « Valider »: « Oui » decides now; « Non » asks to confirm first and decides nothing yet.
    func validate() -> Decision? {
        switch answer {
        case .oui: return .create
        case .non:
            asksRefusalConfirmation = true
            return nil
        }
    }

    /// « Confirmer » in the confirmation: the refusal stands.
    func confirmRefusal() -> Decision {
        asksRefusalConfirmation = false
        return .decline
    }

    /// « Revenir » in the confirmation: back to the question, the selection kept.
    func goBack() {
        asksRefusalConfirmation = false
    }
}
