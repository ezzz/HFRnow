import SwiftUI

/// The reply sheet: a plain text editor, Send and Cancel. Thin: every rule is in `ReplyComposerModel`.
///
/// The editor is SwiftUI's own `TextEditor` with the system keyboard type, so third-party keyboards work (legacy backlog
/// HFR-001) and the text is never rewritten under the cursor; the sheet's keyboard safe area keeps the caret visible.
struct ReplyComposerView: View {
    let model: ReplyComposerModel
    /// Called once with the reason, right before the sheet goes away.
    let onClose: (ReplyComposerModel.CloseReason) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var editorFocused: Bool
    @State private var selection: TextSelection?
    @State private var picker: SmileyPickerModel?
    /// The editor's selection when the picker opened: the sheet takes focus, so the live binding is not trusted.
    @State private var rangeForSmiley: Range<String.Index>?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let message = model.errorMessage {
                    ComposerBanner(text: message, symbol: "exclamationmark.triangle.fill", tint: .orange) {
                        if model.mayHavePosted {
                            Button("Voir le sujet") { Task { await model.checkTopic() } }
                        }
                    }
                }
                if let warning = model.draftWarning {
                    ComposerBanner(text: warning, symbol: "externaldrive.badge.exclamationmark", tint: .secondary) {
                        // Keep and discard cannot close while the store refuses writes: the only exit, as the warning says.
                        if model.canCloseWithoutSaving {
                            Button("Fermer sans enregistrer", role: .destructive) { Task { await model.closeWithoutSaving() } }
                        }
                    }
                }
                editor
            }
            .navigationTitle("Répondre")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .confirmationDialog("Garder ce texte ?", isPresented: askingClose, titleVisibility: .visible) {
                Button("Garder le brouillon") { Task { await model.keepDraftAndClose() } }
                Button("Supprimer le brouillon", role: .destructive) { Task { await model.discardDraftAndClose() } }
                Button("Continuer la saisie", role: .cancel) {}
            } message: {
                Text("Le brouillon est retrouvé à la prochaine réponse dans ce sujet.")
            }
        }
        .sheet(item: $picker, onDismiss: { editorFocused = true }) { picker in
            SmileyPickerView(model: picker) { insertSmiley($0) }
        }
        // Swiping down would close without the choice: blocked while there is text or a send runs.
        .interactiveDismissDisabled(model.closeNeedsChoice || model.isSending)
        .task {
            await model.start()
            editorFocused = true
        }
        .onChange(of: scenePhase) { _, phase in
            if phase != .active { Task { await model.flushDraft() } }
        }
        .onChange(of: model.closeReason) { _, reason in
            guard let reason else { return }
            onClose(reason)
            dismiss()
        }
        .onDisappear {
            // Closed without a choice (account switch rebuilt the screens): keep what was typed.
            Task { await model.flushDraft() }
        }
    }

    private var askingClose: Binding<Bool> {
        Binding(get: { model.isAskingClose }, set: { model.isAskingClose = $0 })
    }

    /// The selected range of the editor, nil without a selection or with several (multi-selection is not used here).
    private var selectedRange: Range<String.Index>? {
        guard case .selection(let range)? = selection?.indices else { return nil }
        return range
    }

    private func openSmileys() {
        let services = model.smileyServices
        rangeForSmiley = selectedRange
        picker = SmileyPickerModel(
            catalogue: SmileyPickerModel.bundledCatalogue(), store: services.store, account: services.account
        )
    }

    private func insertSmiley(_ code: String) {
        guard let caret = model.insert(smiley: code, replacing: rangeForSmiley) else { return }
        selection = TextSelection(insertionPoint: String.Index(utf16Offset: caret, in: model.text))
    }

    private var editor: some View {
        TextEditor(text: Binding(get: { model.text }, set: { model.update(text: $0) }), selection: $selection)
            .focused($editorFocused)
            .font(.body)
            .disabled(!model.canEdit)
            .padding(.horizontal, 12)
            .overlay {
                if model.isRestoring { ProgressView() }
            }
            .accessibilityLabel("Texte de la réponse")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItem(placement: .primaryAction) {
            Button("Smileys", systemImage: "face.smiling", action: openSmileys)
                .disabled(!model.canEdit)
        }
        ToolbarItem(placement: .cancellationAction) {
            Button("Annuler") { Task { await model.requestClose() } }
            .disabled(model.isSending)
        }
        ToolbarItem(placement: .confirmationAction) {
            if model.isSending {
                ProgressView().accessibilityLabel("Envoi en cours")
            } else {
                Button("Envoyer") { Task { await model.send() } }
                    .disabled(!model.canSend)
            }
        }
    }
}

/// A message above the editor, with an optional action.
private struct ComposerBanner<Actions: View>: View {
    let text: String
    let symbol: String
    let tint: Color
    @ViewBuilder let actions: () -> Actions

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).foregroundStyle(tint).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
                actions()
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .padding(.horizontal)
        .padding(.top, 8)
    }
}
