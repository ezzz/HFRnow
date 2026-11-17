import Observation

/// The creation question as a choice (#1014): « Oui » is preselected, and deselecting it raises a confirmation that says what
/// is lost; « Non » is only recorded once that is confirmed. Pure state, so the rule is tested without a view; nothing here
/// creates anything: the caller creates the storage message only for `.create`, which only « Oui » yields.
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

    /// The selected answer: « Oui » at first. Selecting « Non » raises the confirmation at once.
    var answer = Answer.oui {
        didSet {
            if answer == .non, oldValue != .non { asksRefusalConfirmation = true }
        }
    }
    /// True while the confirmation of a « Non » waits for its answer (« Confirmer » or « Revenir »).
    var asksRefusalConfirmation = false

    /// « Valider »: « Oui » decides now; « Non » (reachable only with the confirmation closed by other means) asks again and
    /// decides nothing.
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

    /// « Revenir » in the confirmation: back to the question, « Oui » selected again.
    func goBack() {
        asksRefusalConfirmation = false
        answer = .oui
    }
}
