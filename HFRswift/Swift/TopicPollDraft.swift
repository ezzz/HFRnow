import Foundation
import SwiftUI

struct TopicPollDraft: Equatable {
    var question = ""
    var options = ["", ""]
    var maxChoices = 1
    var allowVisitors = false
    var expiration: Date?

    var validAnswerCount: Int {
        options.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.count
    }

    func validationError(now: Date = Date()) -> String? {
        let trimmedQuestion = question.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedQuestion.isEmpty else { return "Saisissez la question du sondage." }
        guard trimmedQuestion.utf16.count <= 255 else { return "La question est limitée à 255 caractères." }
        guard validAnswerCount >= 2 else { return "Saisissez au moins deux réponses." }
        guard options.count <= 10 else { return "Le sondage est limité à dix réponses." }
        guard options.allSatisfy({ $0.trimmingCharacters(in: .whitespacesAndNewlines).utf16.count <= 255 }) else {
            return "Chaque réponse est limitée à 255 caractères."
        }
        guard (1...validAnswerCount).contains(maxChoices) else {
            return "Le nombre de choix dépasse le nombre de réponses."
        }
        if let expiration, expiration <= now {
            return "Choisissez une date de clôture future."
        }
        return nil
    }

    func formOverrides(calendar: Calendar = .current) -> [String: String] {
        var fields = [
            "have_sondage": "1",
            "textreponse0": question.trimmingCharacters(in: .whitespacesAndNewlines),
            "max_votes": String(maxChoices)
        ]
        for (index, answer) in options.map({ $0.trimmingCharacters(in: .whitespacesAndNewlines) })
            .filter({ !$0.isEmpty }).enumerated() {
            fields["textreponse\(index + 1)"] = answer
        }
        if allowVisitors { fields["allowvisitor"] = "1" }
        if let expiration {
            let parts = calendar.dateComponents([.day, .month, .year, .hour, .minute], from: expiration)
            fields["jour"] = String(format: "%02d", parts.day ?? 0)
            fields["mois"] = String(format: "%02d", parts.month ?? 0)
            fields["annee"] = String(parts.year ?? 0)
            fields["heure"] = String(format: "%02d", parts.hour ?? 0)
            fields["minute"] = String(format: "%02d", parts.minute ?? 0)
        }
        return fields
    }
}

struct TopicPollCreationSheet: View {
    @Environment(\.dismiss) private var dismiss
    @State private var draft: TopicPollDraft
    @State private var hasExpiration: Bool
    @State private var expirationDate: Date
    let onSave: (TopicPollDraft) -> Void

    init(draft: TopicPollDraft, onSave: @escaping (TopicPollDraft) -> Void) {
        _draft = State(initialValue: draft)
        _hasExpiration = State(initialValue: draft.expiration != nil)
        _expirationDate = State(initialValue: draft.expiration ?? Date().addingTimeInterval(86_400))
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Question") {
                    TextField("Question du sondage", text: $draft.question, axis: .vertical)
                        .lineLimit(2...4)
                    Text("\(draft.question.utf16.count)/255")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Section("Réponses") {
                    ForEach(draft.options.indices, id: \.self) { index in
                        HStack {
                            TextField("Réponse \(index + 1)", text: $draft.options[index], axis: .vertical)
                                .lineLimit(1...3)
                            if draft.options.count > 2 {
                                Button(role: .destructive) {
                                    draft.options.remove(at: index)
                                    draft.maxChoices = min(draft.maxChoices, max(1, draft.validAnswerCount))
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel("Supprimer la réponse \(index + 1)")
                            }
                        }
                    }
                    if draft.options.count < 10 {
                        Button("Ajouter une réponse") { draft.options.append("") }
                    }
                }

                Section("Options") {
                    Picker("Choix possibles", selection: $draft.maxChoices) {
                        ForEach(1...max(1, draft.validAnswerCount), id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    Toggle("Autoriser les visiteurs à voter", isOn: $draft.allowVisitors)
                    Toggle("Date de clôture", isOn: $hasExpiration)
                    if hasExpiration {
                        DatePicker("Clôture", selection: $expirationDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    }
                }

                if let error = validatedDraft.validationError() {
                    Section {
                        Text(error).foregroundStyle(.secondary)
                    }
                }
            }
            .navigationTitle("Créer un sondage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        onSave(validatedDraft)
                        dismiss()
                    }
                    .disabled(validatedDraft.validationError() != nil)
                }
            }
        }
    }

    private var validatedDraft: TopicPollDraft {
        var result = draft
        result.expiration = hasExpiration ? expirationDate : nil
        return result
    }
}
