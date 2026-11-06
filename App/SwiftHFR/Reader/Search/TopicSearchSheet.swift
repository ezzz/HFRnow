import SwiftUI

// Port of HFRswift/Swift/TopicSearchSheetView.swift (TopicSearchSheetView) @ 2440d79. Differences: see `TopicSearchModel`.
/// The in-topic search sheet: a word, an author, HFR's answer as a message below them.
struct TopicSearchSheet: View {
    let model: TopicSearchModel
    /// Hands the match over and closes the sheet; the reader follows it once the sheet is gone.
    let open: (ReaderTarget) -> Void
    @Environment(\.dismiss) private var dismiss
    @FocusState private var focus: Field?

    private enum Field { case word, author }

    var body: some View {
        @Bindable var model = model
        NavigationStack {
            Form {
                Section {
                    TextField("Mot-clé", text: $model.word)
                        .focused($focus, equals: .word)
                        .submitLabel(.next)
                        .onSubmit { focus = .author }
                    TextField("Pseudo", text: $model.author)
                        .focused($focus, equals: .author)
                        .submitLabel(.search)
                        .onSubmit(submit)
                } footer: {
                    Text("Renseigne un mot-clé, un pseudo, ou les deux.")
                }
                if case .failed(let message) = model.state {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle").foregroundStyle(.red).font(.footnote)
                    }
                }
            }
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()
            .disabled(model.state == .searching)
            .overlay {
                if model.state == .searching {
                    ProgressView("Recherche en cours…").padding(24).background(.regularMaterial, in: .rect(cornerRadius: 14))
                }
            }
            .navigationTitle("Rechercher")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    // Cancel first: `onDisappear` runs after the dismissal, when a late answer could already be on its way.
                    Button("Annuler") {
                        model.cancel()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(action: submit) { Label("Rechercher", systemImage: "magnifyingglass") }.disabled(!model.canSubmit)
                }
            }
            .onAppear { focus = .word }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        // A swipe down clears the sheet's item at once but `onDisappear` comes after the animation: no dismissal while a
        // search runs, so a late answer never opens a reader behind the user's back ("Annuler" still cancels).
        .interactiveDismissDisabled(model.state == .searching)
        .onDisappear { model.cancel() }
    }

    private func submit() {
        Task {
            guard let target = await model.submit() else { return }
            open(target)
            dismiss()
        }
    }
}
