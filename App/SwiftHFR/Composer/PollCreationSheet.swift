import Foundation
import HFRClient
import SwiftUI

// Port of HFRswift/Swift/TopicPollDraft.swift:56-144 (TopicPollCreationSheet) @ 87fe0d1c (GAP-099). Differences: answers carry
// their own identity, so deleting one never rebinds a field to the wrong row (legacy bound `options[index]` by position); the
// one-line and character rules of `PollDraft` are shown like legacy's other messages; changes are not thrown away without asking
// (#1169, legacy `:124-127` closed at once).
/// "Créer un sondage" (LOT-100): the question, two to ten answers, the number of choices, visitors and the closing date.
struct PollCreationSheet: View {
    /// One answer field.
    private struct Answer: Identifiable {
        let id = UUID()
        var text: String
    }

    @Environment(\.dismiss) private var dismiss
    @State private var question: String
    @State private var answers: [Answer]
    @State private var maxChoices: Int
    @State private var allowsVisitors: Bool
    @State private var hasClosingDate: Bool
    @State private var closingDate: Date
    @State private var isAskingDiscard = false
    /// The poll the sheet opened on: closing asks only once the fields differ from it (#1169).
    private let initial: PollDraft
    let onSave: (PollDraft) -> Void

    /// A sheet opened on `draft` (an empty one adds a poll, the composer's one edits it).
    init(draft: PollDraft, onSave: @escaping (PollDraft) -> Void) {
        _question = State(initialValue: draft.question)
        _answers = State(initialValue: draft.answers.map { Answer(text: $0) })
        _maxChoices = State(initialValue: draft.maxChoices)
        _allowsVisitors = State(initialValue: draft.allowsVisitors)
        _hasClosingDate = State(initialValue: draft.closingDate != nil)
        _closingDate = State(initialValue: draft.closingDate ?? Date().addingTimeInterval(86_400))
        initial = draft
        self.onSave = onSave
    }

    var body: some View {
        NavigationStack {
            Form {
                ThemedSection("Question") {
                    TextField("Question du sondage", text: $question, axis: .vertical)
                        .lineLimit(2...4)
                    Text("\(question.utf16.count)/\(PollDraft.maximumLength)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                answersSection
                ThemedSection("Options") {
                    Picker("Choix possibles", selection: $maxChoices) {
                        ForEach(1...max(1, draft.filledAnswers.count), id: \.self) { count in
                            Text("\(count)").tag(count)
                        }
                    }
                    Toggle("Autoriser les visiteurs à voter", isOn: $allowsVisitors)
                    Toggle("Date de clôture", isOn: $hasClosingDate)
                    if hasClosingDate {
                        DatePicker("Clôture", selection: $closingDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                    }
                }
                if let problem = draft.problem() {
                    Section {
                        Text(ComposerMessages.poll(problem)).foregroundStyle(.secondary).themedListRow()
                    }
                }
            }
            .themedListScreen()
            .navigationTitle("Créer un sondage")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Annuler") {
                        if Self.hasChanges(draft, from: initial) { isAskingDiscard = true } else { dismiss() }
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Ajouter") {
                        onSave(draft)
                        dismiss()
                    }
                    .disabled(draft.problem() != nil)
                }
            }
        }
        .discardConfirmation(
            "Abandonner ce sondage ?", hasChanges: Self.hasChanges(draft, from: initial), isAsking: $isAskingDiscard
        ) { dismiss() }
    }

    /// Whether closing would throw something away (#1169): a field differs from the poll the sheet opened on. Blank text is
    /// nothing to lose, as in the composer: spaces around the question or an answer, and blank answer rows, do not count.
    static func hasChanges(_ current: PollDraft, from initial: PollDraft) -> Bool {
        meaningful(current) != meaningful(initial)
    }

    /// What a poll holds once blank text is left out.
    private static func meaningful(_ poll: PollDraft) -> PollDraft {
        let trimmed = { (text: String) in text.trimmingCharacters(in: .whitespacesAndNewlines) }
        return PollDraft(
            question: trimmed(poll.question), answers: poll.answers.map(trimmed).filter { !$0.isEmpty },
            maxChoices: poll.maxChoices, allowsVisitors: poll.allowsVisitors, closingDate: poll.closingDate
        )
    }

    private var answersSection: some View {
        ThemedSection("Réponses") {
            ForEach(answers) { answer in
                let number = (answers.firstIndex { $0.id == answer.id } ?? 0) + 1
                HStack {
                    TextField("Réponse \(number)", text: text(of: answer.id), axis: .vertical)
                        .lineLimit(1...3)
                    if answers.count > 2 {
                        Button(role: .destructive) {
                            answers.removeAll { $0.id == answer.id }
                            maxChoices = min(maxChoices, max(1, draft.filledAnswers.count))
                        } label: {
                            Image(systemName: "minus.circle.fill")
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Supprimer la réponse \(number)")
                    }
                }
            }
            if answers.count < PollDraft.maximumAnswers {
                Button("Ajouter une réponse") { answers.append(Answer(text: "")) }
            }
        }
    }

    /// The text of answer `id`, wherever it now sits in the list.
    private func text(of id: UUID) -> Binding<String> {
        Binding(
            get: { answers.first { $0.id == id }?.text ?? "" },
            set: { newText in
                guard let index = answers.firstIndex(where: { $0.id == id }) else { return }
                answers[index].text = newText
            }
        )
    }

    /// The poll as the fields stand: the closing date only while its toggle is on (legacy `validatedDraft`).
    private var draft: PollDraft {
        PollDraft(
            question: question, answers: answers.map(\.text), maxChoices: maxChoices, allowsVisitors: allowsVisitors,
            closingDate: hasClosingDate ? closingDate : nil
        )
    }
}
