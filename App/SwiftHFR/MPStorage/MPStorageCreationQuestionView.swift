import SwiftUI

// Port of Classes/MPStorage.m (initOrResetMP:fromView:, the creation alert) @ 87fe0d1c. Differences: a choice with « Oui »
// preselected instead of the Créer / Annuler alert, and a confirmation that says what is lost before a « Non » is recorded
// (operator, 2026-11-17, #1014). GAP-181.
/// The question « Voulez-vous qu'il soit créé ? »: « Oui » selected, « Non » confirmed before it counts.
struct MPStorageCreationQuestionView: View {
    let model: MPStorageSyncModel
    @State private var choice = MPStorageCreationChoice()

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    ThemedRows {
                        Text(MPStorageSyncModel.creationQuestion)
                        Picker("Réponse", selection: $choice.answer) {
                            ForEach(MPStorageCreationChoice.Answer.allCases) { Text($0.label).tag($0) }
                        }
                        .pickerStyle(.inline)
                        .labelsHidden()
                    }
                }
            }
            .themedListScreen()
            .navigationTitle("Stockage MP")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Valider") { apply(choice.validate()) }
                }
            }
            .alert(AlertTitles.mpStorageRefusalQuestion, isPresented: $choice.asksRefusalConfirmation) {
                Button(AlertVerbs.skipMPStorage, role: .destructive) { apply(choice.confirmRefusal()) }
                Button(AlertVerbs.cancel, role: .cancel) { choice.goBack() }
            } message: {
                Text(MPStorageFunctionInfo.refusalMessage)
            }
        }
        // Only « Valider » answers: a swipe down would leave the question open on the model with nothing on screen.
        .interactiveDismissDisabled()
    }

    private func apply(_ decision: MPStorageCreationChoice.Decision?) {
        guard let decision else { return }
        Task { await model.answerCreation(decision == .create) }
    }
}

/// Shows the creation question of `model` as a sheet, where `prompt` says (Réglages or a first write).
struct MPStorageCreationQuestion: ViewModifier {
    let model: MPStorageSyncModel?
    let prompt: MPStorageSyncModel.CreationPrompt

    func body(content: Content) -> some View {
        content.sheet(isPresented: Binding(
            get: { model.map { $0.asksCreation && $0.creationPrompt == prompt } ?? false },
            set: { if !$0 { model?.asksCreation = false } }
        )) {
            if let model { MPStorageCreationQuestionView(model: model) }
        }
    }
}

extension View {
    /// The MP storage creation question for `model`, shown where `prompt` started it (#1014).
    func mpStorageCreationQuestion(
        _ model: MPStorageSyncModel?, prompt: MPStorageSyncModel.CreationPrompt
    ) -> some View {
        modifier(MPStorageCreationQuestion(model: model, prompt: prompt))
    }
}
