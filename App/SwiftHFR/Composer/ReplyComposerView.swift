import SwiftUI

// Port of HFRswift/Swift/AnswerView.swift (AnswerView, reply mode; new topic: sub-category `Picker`, :395-420) @ 2440d79.
// Differences: no formatting, GIF or upload panel yet (LOT-085, 102, 155), smiley picker as a sheet from the toolbar (LOT-104, GAP-087);
// errors say whether anything was posted instead of the toast (GAP-100); draft per topic (GAP-092, UXD).
/// The composer sheet: a plain text editor, Send and Cancel; a new topic adds its subject and sub-category (LOT-089); a new
/// private message adds its recipient and subject
/// (LOT-128, legacy "À :" field, `QuoteMessageViewController.m:306-330` @ 21173e77). Thin: every rule is in
/// `ReplyComposerModel`.
///
/// The editor is SwiftUI's own `TextEditor` with the system keyboard type, so third-party keyboards work (legacy backlog
/// HFR-001) and the text is never rewritten under the cursor; the sheet's keyboard safe area keeps the caret visible.
struct ReplyComposerView: View {
    let model: ReplyComposerModel
    /// Called once with the reason, right before the sheet goes away.
    let onClose: (ReplyComposerModel.CloseReason) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @FocusState private var focused: Field?
    @State private var selection: TextSelection?
    @State private var picker: SmileyPickerModel?
    /// A smiley was inserted by the open picker: focus goes back to the editor when it closes, not after a plain "Fermer".
    @State private var smileyInserted = false
    /// The editor's selection when the picker opened: the sheet takes focus, so the live binding is not trusted.
    @State private var rangeForSmiley: Range<String.Index>?

    private enum Field: Hashable {
        case recipient, subject, text
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let message = model.errorMessage {
                    ComposerBanner(text: message, symbol: "exclamationmark.triangle.fill", tint: .orange) {
                        if model.mayHavePosted {
                            Button(checkTitle) { Task { await model.checkTopic() } }
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
                if model.hasSubjectField { messageFields }
                editor
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .confirmationDialog("Garder ce texte ?", isPresented: askingClose, titleVisibility: .visible) {
                Button("Garder le brouillon") { Task { await model.keepDraftAndClose() } }
                Button("Supprimer le brouillon", role: .destructive) { Task { await model.discardDraftAndClose() } }
                Button("Continuer la saisie", role: .cancel) {}
            } message: {
                Text(keepDraftNote)
            }
        }
        .sheet(item: $picker, onDismiss: { if smileyInserted { focused = .text } }, content: { picker in
            SmileyPickerView(model: picker) { insertSmiley($0) }
        })
        // Swiping down would close without the choice: blocked while there is text or a send runs.
        .interactiveDismissDisabled(model.closeNeedsChoice || model.isSending)
        .task {
            await model.start()
            focused = firstEmptyField
        }
        .task { await model.loadSubcategories() }
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

    /// Where typing starts: the first field of a new private message still empty, else the text.
    private var firstEmptyField: Field {
        guard model.hasSubjectField else { return .text }
        if model.isNewMessage, model.recipient.isEmpty { return .recipient }
        return model.subject.isEmpty ? .subject : .text
    }

    private var title: String {
        model.isNewTopic ? "Nouveau sujet" : model.isNewMessage ? "Nouveau message" : "Répondre"
    }

    private var checkTitle: String {
        model.isNewTopic ? "Voir les sujets" : model.isNewMessage ? "Voir les messages" : "Voir le sujet"
    }

    private var keepDraftNote: String {
        if model.isNewTopic { return "Le brouillon est retrouvé au prochain nouveau sujet dans ce forum." }
        return model.isNewMessage
            ? "Le brouillon est retrouvé au prochain message à ce destinataire."
            : "Le brouillon est retrouvé à la prochaine réponse dans ce sujet."
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
        smileyInserted = false
        picker = SmileyPickerModel(
            catalogue: SmileyPickerModel.bundledCatalogue(), store: services.store, account: services.account
        )
    }

    private func insertSmiley(_ code: String) {
        guard let caret = model.insert(smiley: code, replacing: rangeForSmiley) else { return }
        smileyInserted = true
        selection = TextSelection(insertionPoint: String.Index(utf16Offset: caret, in: model.text))
    }

    private var editor: some View {
        TextEditor(text: Binding(get: { model.text }, set: { model.update(text: $0) }), selection: $selection)
            .focused($focused, equals: .text)
            .scaledFont(.body)
            .disabled(!model.canEdit)
            .padding(.horizontal, 12)
            .overlay {
                if model.isRestoring { ProgressView() }
            }
            .accessibilityLabel(model.isNewMessage || model.isNewTopic ? "Texte du message" : "Texte de la réponse")
    }

    /// Recipient (private message) or sub-category (topic) and subject, one line each, like HFR's own forms (`R45a`, `R45b`).
    private var messageFields: some View {
        VStack(spacing: 0) {
            if model.isNewMessage {
                TextField("Destinataire", text: Binding(get: { model.recipient }, set: { model.update(recipient: $0) }))
                    .focused($focused, equals: .recipient)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .submitLabel(.next)
                    .onSubmit { focused = .subject }
                    .accessibilityLabel("Pseudo du destinataire")
                    .padding(.vertical, 10)
                Divider()
            }
            if model.isNewTopic {
                subcategoryRow
                Divider()
            }
            TextField("Sujet", text: Binding(get: { model.subject }, set: { model.update(subject: $0) }))
                .focused($focused, equals: .subject)
                .submitLabel(.next)
                .onSubmit { focused = .text }
                .padding(.vertical, 10)
            Divider()
        }
        .scaledFont(.body)
        .disabled(!model.canEdit)
        .padding(.horizontal, 16)
    }

    /// The form's sub-categories as a menu (legacy `Picker`, `AnswerView.swift:411`); a failed read says so and offers a retry.
    @ViewBuilder
    private var subcategoryRow: some View {
        if model.picker.isLoading {
            HStack {
                Text("Sous-catégorie")
                Spacer()
                ProgressView().accessibilityLabel("Chargement des sous-catégories")
            }
            .padding(.vertical, 10)
        } else if !model.picker.options.isEmpty {
            Picker("Sous-catégorie", selection: Binding(
                get: { model.picker.selected ?? "" }, set: { model.select(subcategory: $0) }
            )) {
                ForEach(model.picker.options, id: \.value) { option in
                    Text(option.label).tag(option.value)
                }
            }
            .pickerStyle(.menu)
            .padding(.vertical, 2)
        } else if let warning = model.picker.warning {
            VStack(alignment: .leading, spacing: 6) {
                Text(warning).scaledFont(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("Réessayer") { Task { await model.loadSubcategories() } }
            }
            .padding(.vertical, 10)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
                Text(text).scaledFont(.callout).fixedSize(horizontal: false, vertical: true)
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
