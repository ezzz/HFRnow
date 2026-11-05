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
    @State private var formatting: ComposerFormattingModel
    @State private var selection: TextSelection?

    init(model: ReplyComposerModel, onClose: @escaping (ReplyComposerModel.CloseReason) -> Void) {
        self.model = model
        self.onClose = onClose
        _formatting = State(initialValue: ComposerFormattingModel(composer: model, clipboard: SystemClipboard()))
    }

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
                FormattingToolbar(model: formatting) { editorFocused = true }
            }
            .navigationTitle("Répondre")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .alert("Utiliser le presse-papiers ?", isPresented: askingClipboard, presenting: formatting.pending) { pending in
                switch pending {
                case .link:
                    Button("Non", role: .cancel) { formatting.declinePending() }
                    Button("Oui") { formatting.acceptPending() }
                case .formatting:
                    Button("Sans le presse-papiers", role: .cancel) { formatting.declinePending() }
                    Button("Insérer") { formatting.acceptPending() }
                }
            } message: { pending in
                Text(pending.message)
            }
            .confirmationDialog("Garder ce texte ?", isPresented: askingClose, titleVisibility: .visible) {
                Button("Garder le brouillon") { Task { await model.keepDraftAndClose() } }
                Button("Supprimer le brouillon", role: .destructive) { Task { await model.discardDraftAndClose() } }
                Button("Continuer la saisie", role: .cancel) {}
            } message: {
                Text("Le brouillon est retrouvé à la prochaine réponse dans ce sujet.")
            }
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

    private var askingClipboard: Binding<Bool> {
        Binding(
            get: { formatting.pending != nil },
            set: { if !$0 { formatting.dismissPending(); editorFocused = true } }
        )
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
            .onChange(of: selection) { _, newValue in
                guard let newValue else { return }
                formatting.selectedRange = Self.range(of: newValue, in: model.text)
            }
            .onChange(of: formatting.cursorRevision) {
                // The edit already changed the text: place the caret where the engine says, never at the end.
                let text = model.text
                let offset = min(formatting.selectedRange.location, text.utf16.count)
                selection = TextSelection(insertionPoint: String.Index(utf16Offset: offset, in: text))
                editorFocused = true
            }
    }

    /// The first selected range as a UTF-16 `NSRange`.
    private static func range(of selection: TextSelection, in text: String) -> NSRange {
        switch selection.indices {
        case .selection(let range): NSRange(range, in: text)
        case .multiSelection(let set): set.ranges.first.map { NSRange($0, in: text) } ?? NSRange(location: text.utf16.count, length: 0)
        @unknown default: NSRange(location: text.utf16.count, length: 0)
        }
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
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
