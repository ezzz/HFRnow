import HFRClient
import SwiftUI

// Port of HFRswift/Swift/AnswerView.swift:873-906 (the poll row of `ComposerHeader`) and :523-528 (its sheet) @ 87fe0d1c (GAP-099).
// Differences: a failed read is retried from the sub-category row, which shows the same failure with "Réessayer".
/// "Ajouter un sondage" / "Modifier le sondage" and "Retirer" (LOT-100), with why the button is off, or the poll's question.
struct ComposerPollRow: View {
    let model: ReplyComposerModel
    @State private var isEditing = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Button(model.poll.draft == nil ? "Ajouter un sondage" : "Modifier le sondage") { isEditing = true }
                    .disabled(model.poll.availability != .offered)
                if model.poll.draft != nil {
                    Spacer()
                    Button("Retirer", role: .destructive) { model.removePoll() }
                }
            }
            if let note {
                Text(note).scaledFont(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            if let draft = model.poll.draft {
                Text(draft.question).scaledFont(.caption).foregroundStyle(.secondary).lineLimit(2)
                Text("Le sondage sera créé lors de l’envoi du message.").scaledFont(.caption2).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(isPresented: $isEditing) {
            PollCreationSheet(draft: model.poll.draft ?? PollDraft()) { model.set(poll: $0) }
        }
    }

    /// Why the button is off (legacy `AnswerView.swift:884-897`), or what stops the poll set from being sent.
    private var note: String? {
        switch model.poll.availability {
        case .loading:
            return "Chargement des options de sondage…"
        case .failed:
            return "Les options de sondage n’ont pas pu être lues."
        case .notOffered:
            return model.isNewTopic
                ? "Le forum ne propose pas de sondage à cette étape. Crée le sujet, puis édite son premier message."
                : "Le formulaire du forum ne propose pas la création d’un sondage pour ce message."
        case .offered:
            return model.poll.draft?.problem().map(ComposerMessages.poll)
        }
    }
}
