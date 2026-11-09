import SwiftUI

// Port of HFRswift/Swift/AppSettingsView.swift (ProfileFilterListEditorView, `:581-700`) @ 2440d79. Differences: see
// `PseudoListEditorModel`; the swipe removes through `.onDelete` as legacy, the "Modifier" button is kept.
/// One list editor: a field with "Ajouter", the sorted pseudos with swipe to remove.
struct PseudoListEditorView: View {
    @State private var model: PseudoListEditorModel

    /// An editor of `kind` over `manager`.
    init(kind: PseudoListKind, manager: PseudoListManager) {
        _model = State(initialValue: PseudoListEditorModel(kind: kind, manager: manager))
    }

    var body: some View {
        @Bindable var model = model
        Form {
            if model.requiresAccount {
                Section { Text("Connecte-toi pour gérer la liste noire de ton compte.").foregroundStyle(.secondary) }
            } else {
                Section {
                    HStack {
                        TextField("Pseudo", text: $model.draft)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                            .submitLabel(.done)
                            .onSubmit { Task { await model.add() } }
                        Button("Ajouter") { Task { await model.add() } }
                            .disabled(!model.canAdd)
                    }
                }
                if let unreadable = model.unreadableMessage {
                    Section {
                        Text(unreadable).foregroundStyle(.secondary)
                        Button("Réessayer") { Task { await model.retry() } }
                    }
                } else {
                    Section {
                        if model.pseudos.isEmpty {
                            if model.hasLoaded { Text(model.kind.emptyMessage).foregroundStyle(.secondary) }
                        } else {
                            ForEach(model.pseudos, id: \.self) { Text(verbatim: $0) }
                                .onDelete { model.remove(at: $0) }
                        }
                    } header: {
                        Text(model.kind.title)
                    } footer: {
                        Text(model.kind.footer)
                    }
                }
            }
        }
        .navigationTitle(model.kind.title)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) { EditButton().disabled(model.pseudos.isEmpty) }
        }
        .task { await model.load() }
        .alert("Erreur", isPresented: Binding(get: { model.errorMessage != nil }, set: { if !$0 { model.errorMessage = nil } })) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(model.errorMessage ?? "")
        }
    }
}
